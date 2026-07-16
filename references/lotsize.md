# MQL5 Lot Size Helpers

File này gom các pattern tính lot size thường dùng trong EA MQL5.

Nguyên tắc:
- `NormalizeLotUp()` dùng khi cần đạt ít nhất một mục tiêu tiền, ví dụ recovery/profit target.
- `NormalizeLotDown()` dùng khi cần không vượt quá risk cap.
- Normalize volume theo `lotMin + n * lotStep`, không hard-code `NormalizeDouble(lot, 2)`.
- Cách tính thủ công nhanh nhưng phụ thuộc `SYMBOL_TRADE_TICK_VALUE`.
- Cách dùng `OrderCalcProfit()` đáng tin hơn khi đã biết `orderType`, `priceOpen`, `priceClose`.
- Cả hai cách đều không tự tính commission/swap tương lai. Nếu cần net profit chính xác, phải cộng buffer hoặc quản lý đóng lệnh theo floating profit.

---

## Volume Helpers

```mq5
string ResolveSymbol(const string symbol = "")
{
   if(StringLen(symbol) > 0)
      return symbol;

   return _Symbol;
}

bool GetVolumeInfo(const string symbol, double &lotMin, double &lotMax, double &lotStep)
{
   string s = ResolveSymbol(symbol);

   lotMin  = SymbolInfoDouble(s, SYMBOL_VOLUME_MIN);
   lotMax  = SymbolInfoDouble(s, SYMBOL_VOLUME_MAX);
   lotStep = SymbolInfoDouble(s, SYMBOL_VOLUME_STEP);

   if(lotMin <= 0.0 || lotMax <= 0.0 || lotStep <= 0.0 || lotMax < lotMin)
   {
      PrintFormat("Invalid volume info: symbol=%s min=%.8f max=%.8f step=%.8f",
                  s, lotMin, lotMax, lotStep);
      return false;
   }

   return true;
}

int GetVolumeDigitsByStep(double lotStep)
{
   int digits = 0;
   double step = lotStep;

   while(digits < 8 && MathAbs(step - MathRound(step)) > 0.000000001)
   {
      step *= 10.0;
      digits++;
   }

   return digits;
}

double NormalizeLotUp(double lot, const string symbol = "")
{
   double lotMin = 0.0;
   double lotMax = 0.0;
   double lotStep = 0.0;

   if(!GetVolumeInfo(symbol, lotMin, lotMax, lotStep))
      return lot;

   if(lot <= 0.0)
      return 0.0;

   int digits = GetVolumeDigitsByStep(lotStep);

   if(lot <= lotMin)
      return NormalizeDouble(lotMin, digits);

   double normalizedLot = lotMin + MathCeil(((lot - lotMin) / lotStep) - 0.000000001) * lotStep;
   normalizedLot = MathMin(normalizedLot, lotMax);

   return NormalizeDouble(normalizedLot, digits);
}

double NormalizeLotDown(double lot, const string symbol = "", const bool allowZeroIfBelowMin = false)
{
   double lotMin = 0.0;
   double lotMax = 0.0;
   double lotStep = 0.0;

   if(!GetVolumeInfo(symbol, lotMin, lotMax, lotStep))
      return lot;

   if(lot <= 0.0)
      return 0.0;

   if(allowZeroIfBelowMin && lot < lotMin)
      return 0.0;

   int digits = GetVolumeDigitsByStep(lotStep);

   if(lot <= lotMin)
      return NormalizeDouble(lotMin, digits);

   double normalizedLot = lotMin + MathFloor(((lot - lotMin) / lotStep) + 0.000000001) * lotStep;
   normalizedLot = MathMin(normalizedLot, lotMax);

   return NormalizeDouble(normalizedLot, digits);
}
```

---

## Planned Open/Close Prices

Dùng helper này khi cần dựng giá `priceOpen` và `priceClose` dự kiến từ khoảng cách points. `isProfitTarget=true` nghĩa là close theo hướng có lời; `false` nghĩa là close theo hướng lỗ.

```mq5
bool GetPlannedOpenClosePrices(const string symbol,
                               const ENUM_ORDER_TYPE orderType,
                               const double distancePoints,
                               const bool isProfitTarget,
                               double &priceOpen,
                               double &priceClose)
{
   string s = ResolveSymbol(symbol);

   if(distancePoints <= 0.0)
      return false;

   double point = SymbolInfoDouble(s, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);

   if(point <= 0.0 || digits < 0)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(s, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   double distancePrice = distancePoints * point;

   if(orderType == ORDER_TYPE_BUY)
   {
      priceOpen = tick.ask;
      priceClose = isProfitTarget ? priceOpen + distancePrice
                                  : priceOpen - distancePrice;
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      priceOpen = tick.bid;
      priceClose = isProfitTarget ? priceOpen - distancePrice
                                  : priceOpen + distancePrice;
   }
   else
   {
      return false;
   }

   priceOpen = NormalizeDouble(priceOpen, digits);
   priceClose = NormalizeDouble(priceClose, digits);

   return (priceOpen > 0.0 && priceClose > 0.0);
}
```

---

## CalculateLotSize 1: Distance Points + Target Money

Dùng khi biết khoảng cách SL/TP theo points và số tiền muốn risk/win theo account currency.

Ví dụ:
- Risk `$10` với SL cách `3000` points.
- Muốn TP thắng `$10` với TP cách `5000` points.

Hàm này tính `profitPerLot` thủ công. Cách này nhanh nhưng chỉ là approximation trên một số symbol, vì broker có thể có tick value profit/loss khác nhau hoặc chuyển đổi currency phức tạp. Khi tính risk nghiêm túc, ưu tiên phiên bản dùng `OrderCalcProfit()`.

```mq5
profitPerLot = (distancePoints * point / tickSize) * tickValue;
lot = targetMoney / profitPerLot;
```

```mq5
double CalculateLotSize(const string symbol,
                        const double distancePoints,
                        const double targetMoney,
                        const bool roundUp = true)
{
   string s = ResolveSymbol(symbol);

   if(distancePoints <= 0.0 || targetMoney <= 0.0)
      return 0.0;

   double tickValue = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(s, SYMBOL_POINT);

   if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
   {
      PrintFormat("Invalid tick info: symbol=%s tickValue=%.8f tickSize=%.8f point=%.8f",
                  s, tickValue, tickSize, point);
      return 0.0;
   }

   double profitPerLot = (distancePoints * point / tickSize) * tickValue;
   if(profitPerLot <= 0.0)
      return 0.0;

   double rawLot = targetMoney / profitPerLot;

   if(roundUp)
      return NormalizeLotUp(rawLot, s);

   return NormalizeLotDown(rawLot, s, true);
}
```

Usage:

```mq5
double riskLot = CalculateLotSize(_Symbol, InpSL_Points, 10.0, false); // risk cap
double winLot  = CalculateLotSize(_Symbol, InpTP_Points, 10.0, true);  // reach target
```

---

## CalculateLotSize 2: Open Price + Close Price + Target Money

Dùng khi đã biết `priceOpen`, `priceClose`, và số tiền muốn risk/win. Hàm này dùng `OrderCalcProfit()` để tính profit của một `referenceLot`, sau đó suy ra `profitPerLot`.

Ưu điểm:
- Tôn trọng logic profit của MT5 theo symbol/order type.
- Hữu ích cho CFD, crypto, metal, cross-currency account, hoặc symbol có tick value phức tạp.
- Phân biệt đúng BUY/SELL và giá open/close thực tế.

```mq5
double CalculateLotSize(const string symbol,
                        const ENUM_ORDER_TYPE orderType,
                        const double priceOpen,
                        const double priceClose,
                        const double targetMoney,
                        const bool roundUp = true)
{
   string s = ResolveSymbol(symbol);

   if(targetMoney <= 0.0 || priceOpen <= 0.0 || priceClose <= 0.0 || priceOpen == priceClose)
      return 0.0;

   if(orderType != ORDER_TYPE_BUY && orderType != ORDER_TYPE_SELL)
      return 0.0;

   double referenceLot = NormalizeLotUp(1.0, s);
   if(referenceLot <= 0.0)
      return 0.0;

   double referenceProfit = 0.0;
   ResetLastError();
   if(!OrderCalcProfit(orderType, s, referenceLot, priceOpen, priceClose, referenceProfit))
   {
      PrintFormat("OrderCalcProfit failed: symbol=%s error=%d", s, GetLastError());
      return 0.0;
   }

   double profitPerLot = MathAbs(referenceProfit) / referenceLot;
   if(profitPerLot <= 0.0)
   {
      PrintFormat("Invalid OrderCalcProfit result: symbol=%s refLot=%.4f refProfit=%.2f",
                  s, referenceLot, referenceProfit);
      return 0.0;
   }

   double rawLot = targetMoney / profitPerLot;

   if(roundUp)
      return NormalizeLotUp(rawLot, s);

   return NormalizeLotDown(rawLot, s, true);
}
```

Usage với helper dựng giá:

```mq5
double priceOpen = 0.0;
double priceClose = 0.0;

if(GetPlannedOpenClosePrices(_Symbol, ORDER_TYPE_BUY, InpTP_Points, true, priceOpen, priceClose))
{
   double lot = CalculateLotSize(_Symbol, ORDER_TYPE_BUY, priceOpen, priceClose, 10.0, true);
}
```

Usage với giá có sẵn:

```mq5
double lotByOrderCalc = CalculateLotSize(_Symbol,
                                         ORDER_TYPE_SELL,
                                         sellOpenPrice,
                                         sellTpPrice,
                                         10.0,
                                         true);
```

---

## Choosing Up vs Down

```mq5
// Recovery hoặc profit target: cần đạt ít nhất targetMoney
double recoveryLot = CalculateLotSize(_Symbol, ORDER_TYPE_BUY, openPrice, tpPrice, lossToRecover, true);

// Risk cap: không muốn vượt quá targetMoney
double riskLot = CalculateLotSize(_Symbol, slPoints, maxLossMoney, false);
```

Nếu `NormalizeLotDown(..., allowZeroIfBelowMin=true)` trả `0.0`, raw lot nhỏ hơn min lot của broker. Khi đó hoặc bỏ qua lệnh, hoặc chấp nhận min lot và biết rằng risk/profit sẽ lệch khỏi target.
