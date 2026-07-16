# MQL5 Trading Patterns

## CTrade class - Setup chuẩn

```mq5
#include <Trade\Trade.mqh>

CTrade trade;

input long InpMagicNumber = 12345;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);       // max slippage in points
   trade.SetTypeFillingBySymbol(_Symbol); // tránh hard-code FOK/IOC sai với broker

   return INIT_SUCCEEDED;
}
```

Không hard-code `ORDER_FILLING_FOK` cho mọi symbol. Nếu broker reject filling mode, kiểm tra `SYMBOL_FILLING_MODE` hoặc dùng `SetTypeFillingBySymbol()`.

---

## Trade permission và retcode

`CTrade.Buy()` / `Sell()` trả `true` nghĩa là request được build/gửi qua lớp `CTrade`, chưa đủ để kết luận lệnh đã thành công. Luôn kiểm tra `ResultRetcode()`.

```mq5
bool IsTradeAllowed()
{
   return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
          (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}

bool IsTradeRetcodeSuccess(const uint retcode)
{
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL ||
          retcode == TRADE_RETCODE_PLACED;
}

bool CheckTradeResult(const string action, const bool requestSent)
{
   uint retcode = trade.ResultRetcode();
   if(requestSent && IsTradeRetcodeSuccess(retcode))
      return true;

   PrintFormat("%s failed: requestSent=%s retcode=%u (%s)",
               action,
               requestSent ? "true" : "false",
               retcode,
               trade.ResultRetcodeDescription());
   return false;
}

bool DeletePendingOrderByTicket(const ulong ticket)
{
   return CheckTradeResult("OrderDelete", trade.OrderDelete(ticket));
}
```

Nếu `IsTradeAllowed()` trả `false`, kiểm tra nút **Algo Trading** trên terminal, tab Common của EA, quyền trade của account, và log initialization trước khi nghi broker reject lệnh.

---

## Kiểm tra market status — IsMarketOpen()

`IsTradeAllowed()` và `IsMarketOpen()` là **hai check độc lập** — phải dùng cả hai trước khi trade:

| Hàm | Kiểm tra gì | Khi nào fail |
|---|---|---|
| `IsTradeAllowed()` | Terminal, account, EA permission | Algo Trading tắt, account bị block, EA không có quyền trade |
| `IsMarketOpen()` | Trạng thái market của symbol | Ngoài giờ giao dịch, symbol bị suspend → retcode `10018` |

`IsTradeAllowed()` trả `true` ngay cả khi market đóng cửa — đó là lý do cần check thêm `IsMarketOpen()`.

`ENUM_SYMBOL_TRADE_MODE` có các giá trị:

| Giá trị | Ý nghĩa |
|---|---|
| `SYMBOL_TRADE_MODE_FULL` (4) | Giao dịch bình thường — mở/đóng/modify đều được |
| `SYMBOL_TRADE_MODE_CLOSEONLY` (3) | Chỉ được đóng lệnh, không mở mới |
| `SYMBOL_TRADE_MODE_LONGONLY` (1) | Chỉ được mở Buy |
| `SYMBOL_TRADE_MODE_SHORTONLY` (2) | Chỉ được mở Sell |
| `SYMBOL_TRADE_MODE_DISABLED` (0) | Không giao dịch được |

**Lưu ý quan trọng:** `SYMBOL_TRADE_MODE_FULL` **không đủ tin cậy** để phát hiện market đóng cửa holiday. Một số broker giữ nguyên mode `FULL` nhưng ngừng nhận lệnh và trả retcode `10018`. Cần kết hợp thêm **tick freshness check**.

Với symbol thanh khoản thấp, cổ phiếu ít tick, hoặc Strategy Tester dùng dữ liệu thưa, `60` giây có thể quá chặt. Đưa ngưỡng thành input để tăng lên `300` giây hoặc set `0` để tắt freshness check khi đã biết môi trường test cần vậy.

```mq5
input int InpMarketOpenMaxTickAgeSec = 60; // 0 = disable tick freshness check

datetime LastTickTime()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return 0;
   return tick.time;
}

bool IsMarketOpen()
{
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE)
      != SYMBOL_TRADE_MODE_FULL) return false;

   datetime tickTime = LastTickTime();
   if(tickTime == 0) return false;

   if(InpMarketOpenMaxTickAgeSec <= 0)
      return true;

   return (TimeTradeServer() - tickTime) <= InpMarketOpenMaxTickAgeSec;
}
```

**Mặc định:** chỉ cần `if(!IsMarketOpen()) return;` để bỏ qua khi market đóng. Không cố vào lệnh hoặc đóng lệnh khi thị trường đóng cửa. Chỉ xử lý pending signal khi user yêu cầu rõ ràng — xem cuối file.

---

## Validate stops level

SL/TP và pending price phải cách giá tham chiếu ít nhất `SYMBOL_TRADE_STOPS_LEVEL` points. Khi modify lệnh/position đang mở, cần chú ý thêm `SYMBOL_TRADE_FREEZE_LEVEL`.

```mq5
bool ValidateStopsLevel(const string symbol,
                        const ENUM_ORDER_TYPE orderType,
                        const double entryPrice,
                        const double sl,
                        const double tp)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);

   if(point <= 0.0)
      return false;

   if(stopsLevel <= 0)
      return true;

   double minDistance = stopsLevel * point;

   if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP)
   {
      if(sl > 0.0 && entryPrice - sl < minDistance) return false;
      if(tp > 0.0 && tp - entryPrice < minDistance) return false;
      return true;
   }

   if(orderType == ORDER_TYPE_SELL || orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP)
   {
      if(sl > 0.0 && sl - entryPrice < minDistance) return false;
      if(tp > 0.0 && entryPrice - tp < minDistance) return false;
      return true;
   }

   return false;
}
```

---

## Mở lệnh Buy / Sell

Ví dụ dưới giả định đã dùng helper volume trong [lotsize.md](lotsize.md), ví dụ `NormalizeLotDown()` hoặc `NormalizeLotUp()`.

```mq5
if(!IsTradeAllowed()) return;
if(!IsMarketOpen()) return;

MqlTick tick;
if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   return;

double volume = NormalizeLotDown(InpLotSize, _Symbol);
if(volume <= 0.0) return;

double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

// Buy
double slBuy = NormalizeDouble(tick.ask - 100 * point, digits);
double tpBuy = NormalizeDouble(tick.ask + 200 * point, digits);
if(ValidateStopsLevel(_Symbol, ORDER_TYPE_BUY, tick.ask, slBuy, tpBuy))
   CheckTradeResult("Buy", trade.Buy(volume, _Symbol, tick.ask, slBuy, tpBuy, "comment"));

// Sell
double slSell = NormalizeDouble(tick.bid + 100 * point, digits);
double tpSell = NormalizeDouble(tick.bid - 200 * point, digits);
if(ValidateStopsLevel(_Symbol, ORDER_TYPE_SELL, tick.bid, slSell, tpSell))
   CheckTradeResult("Sell", trade.Sell(volume, _Symbol, tick.bid, slSell, tpSell, "comment"));
```

---

## Pending orders (Buy/Sell Stop, Limit)

```mq5
if(!IsTradeAllowed()) return;
if(!IsMarketOpen()) return;

double volume = NormalizeLotDown(InpLotSize, _Symbol);
if(volume <= 0.0) return;

double price  = NormalizeDouble(entryPrice, _Digits);
double sl     = NormalizeDouble(slPrice, _Digits);
double tp     = NormalizeDouble(tpPrice, _Digits);
datetime expiry = 0;   // 0 = GTC

if(ValidateStopsLevel(_Symbol, ORDER_TYPE_BUY_STOP, price, sl, tp))
   CheckTradeResult("BuyStop",
                    trade.BuyStop(volume, price, _Symbol, sl, tp, ORDER_TIME_GTC, expiry, "comment"));

if(ValidateStopsLevel(_Symbol, ORDER_TYPE_SELL_STOP, price, sl, tp))
   CheckTradeResult("SellStop",
                    trade.SellStop(volume, price, _Symbol, sl, tp, ORDER_TIME_GTC, expiry, "comment"));

if(ValidateStopsLevel(_Symbol, ORDER_TYPE_BUY_LIMIT, price, sl, tp))
   CheckTradeResult("BuyLimit",
                    trade.BuyLimit(volume, price, _Symbol, sl, tp, ORDER_TIME_GTC, expiry, "comment"));

if(ValidateStopsLevel(_Symbol, ORDER_TYPE_SELL_LIMIT, price, sl, tp))
   CheckTradeResult("SellLimit",
                    trade.SellLimit(volume, price, _Symbol, sl, tp, ORDER_TIME_GTC, expiry, "comment"));
```

Pending order price cũng phải nằm đúng phía thị trường: Buy Stop trên Ask, Sell Stop dưới Bid, Buy Limit dưới Ask, Sell Limit trên Bid.

---

## Account và symbol info

```mq5
double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
int    spread  = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
int    stops   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
int    freeze  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
```

Không hard-code volume digits như `NormalizeDouble(lot, 2)`. Dùng helper trong [lotsize.md](lotsize.md) để round theo `SYMBOL_VOLUME_STEP`.

---

## Pattern: pending signal khi market đóng cửa *(chỉ dùng khi được yêu cầu)*

> Mặc định không cần section này. Chỉ implement khi user yêu cầu rõ ràng là cần giữ lại tín hiệu khi market đóng cửa.

EA chạy theo nến đóng có thể detect signal đúng lúc market đóng. Nếu bỏ qua luôn, signal có thể mất vĩnh viễn khi bar đã bị mark processed.

Giải pháp gồm **hai lớp bảo vệ**:
1. **Pre-check** bằng `IsMarketOpen()` — lưu pending nếu market đóng
2. **Fallback** trong `ExecuteSignal` bắt retcode `10018` — lưu pending kể cả khi `IsMarketOpen()` trả sai

```mq5
//--- Global: 1=buy pending, -1=sell pending, 0=none
int g_pendingSignal = 0;

void OnTick()
{
   // Dung helper IsNewBarCandidate/MarkBarProcessed trong ea_base.mq5 hoac pitfalls.md.
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool newBar     = IsNewBarCandidate(currentBarTime);
   bool marketOpen = IsMarketOpen();

   if(!IsTradeAllowed()) return;

   // Retry pending signal khi market mo lai
   if(g_pendingSignal != 0 && marketOpen)
   {
      if(ExecuteSignal(g_pendingSignal))
         g_pendingSignal = 0;
      // false = van gap 10018, giu pending, retry tick tiep
   }

   if(!newBar) return;

   int signal = 0; // 1 hoac -1
   if(!ReadSignalData(signal)) return; // placeholder: CopyBuffer/CopyClose + detect signal

   MarkBarProcessed(currentBarTime);

   if(signal == 0) return;

   if(marketOpen)
   {
      if(!ExecuteSignal(signal))
         g_pendingSignal = signal; // fallback: IsMarketOpen() sai nhung broker tra 10018
   }
   else
   {
      g_pendingSignal = signal;    // market closed ro rang
   }
}

// Tra true neu thanh cong, false neu gap retcode 10018
bool ExecuteSignal(int signal)
{
   if(signal ==  1) { /* CloseSellPositions(); OpenBuy();  */ }
   if(signal == -1) { /* CloseBuyPositions();  OpenSell(); */ }

   if(trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED)
      return false;
   return true;
}
```

Signal mới luôn ghi đè `g_pendingSignal` cũ — signal mới nhất từ indicator là thông tin cập nhật nhất.

---

## Danh sách toàn bộ các Methods của lớp CTrade

> [!IMPORTANT]
> **CẢNH BÁO QUAN TRỌNG:** Lớp `CTrade` **KHÔNG** có các phương thức thiết lập cấu hình Stop Loss / Take Profit riêng lẻ dạng `SetStopLoss(double sl)` hay `SetTakeProfit(double tp)`.
> - Để cài đặt SL/TP cho các lệnh giao dịch trực tiếp, các giá trị này phải được truyền vào tham số khi gọi hàm giao dịch, ví dụ: `trade.Buy(volume, symbol, price, sl, tp, comment)`.
> - Để thay đổi SL/TP của vị thế đang mở, sử dụng hàm `trade.PositionModify(symbol, sl, tp)`.
> - Tuyệt đối không gọi các hàm không tồn tại để tránh lỗi compile.

Bảng dưới đây liệt kê đầy đủ tất cả các method hợp lệ của `CTrade` từ tài liệu chính thức:

### 1. Thiết lập tham số (Setting parameters)
| Tên Method | Mô tả |
| :--- | :--- |
| `LogLevel(int level)` | Cài đặt mức độ ghi nhật ký hoạt động (log level) |
| `SetExpertMagicNumber(long magic)` | Thiết lập Magic Number định danh cho EA |
| `SetDeviationInPoints(ulong deviation)` | Thiết lập độ lệch giá tối đa cho phép (slippage) bằng points |
| `SetTypeFilling(ENUM_ORDER_TYPE_FILLING filling)` | Thiết lập chế độ khớp lệnh (FOK, IOC, v.v.) |
| `SetTypeFillingBySymbol(string symbol)` | Tự động thiết lập chế độ khớp lệnh phù hợp nhất cho symbol chỉ định |
| `SetAsyncMode(bool mode)` | Bật/tắt chế độ giao dịch bất đồng bộ (asynchronous mode) |
| `SetMarginMode()` | Thiết lập chế độ tính toán ký quỹ (margin) phù hợp với tài khoản |

### 2. Thao tác với Lệnh chờ (Operations with orders)
| Tên Method | Mô tả |
| :--- | :--- |
| `OrderOpen(...)` | Đặt lệnh chờ với các tham số cụ thể trong cấu trúc yêu cầu |
| `OrderModify(...)` | Sửa đổi các tham số của một lệnh chờ đang hoạt động |
| `OrderDelete(ulong ticket)` | Xóa lệnh chờ theo ticket |

### 3. Thao tác với Vị thế (Operations with positions)
| Tên Method | Mô tả |
| :--- | :--- |
| `PositionOpen(...)` | Mở vị thế giao dịch với các tham số cụ thể |
| `PositionModify(string symbol, double sl, double tp)` hoặc `(ulong ticket, double sl, double tp)` | Sửa đổi Stop Loss và Take Profit cho vị thế đang mở |
| `PositionClose(string symbol, ulong deviation)` hoặc `(ulong ticket, ulong deviation)` | Đóng vị thế theo symbol hoặc ticket vị thế |
| `PositionClosePartial(string symbol, double volume, ulong deviation)` hoặc `(ulong ticket, double volume, ulong deviation)` | Đóng một phần khối lượng của vị thế đang mở |
| `PositionCloseBy(ulong ticket, ulong ticket_by)` | Đóng vị thế đối ứng (hedging) bằng một ticket vị thế ngược chiều |

### 4. Các phương thức giao dịch bổ sung (Additional methods)
| Tên Method | Mô tả |
| :--- | :--- |
| `Buy(double volume, string symbol, double price, double sl, double tp, string comment)` | Mở vị thế Buy (Long) trực tiếp |
| `Sell(double volume, string symbol, double price, double sl, double tp, string comment)` | Mở vị thế Sell (Short) trực tiếp |
| `BuyLimit(double volume, double price, string symbol, double sl, double tp, ENUM_ORDER_TYPE_TIME type_time, datetime expiration, string comment)` | Đặt lệnh chờ Buy Limit |
| `BuyStop(double volume, double price, string symbol, double sl, double tp, ENUM_ORDER_TYPE_TIME type_time, datetime expiration, string comment)` | Đặt lệnh chờ Buy Stop |
| `SellLimit(double volume, double price, string symbol, double sl, double tp, ENUM_ORDER_TYPE_TIME type_time, datetime expiration, string comment)` | Đặt lệnh chờ Sell Limit |
| `SellStop(double volume, double price, string symbol, double sl, double tp, ENUM_ORDER_TYPE_TIME type_time, datetime expiration, string comment)` | Đặt lệnh chờ Sell Stop |

### 5. Truy cập thuộc tính của Yêu cầu gần nhất (Access to the last request parameters)
| Tên Method | Mô tả |
| :--- | :--- |
| `Request()` | Lấy bản sao cấu trúc yêu cầu giao dịch gần nhất (`MqlTradeRequest`) |
| `RequestAction()` | Lấy loại hoạt động giao dịch gần nhất |
| `RequestActionDescription()` | Lấy mô tả dạng chuỗi của loại hoạt động giao dịch gần nhất |
| `RequestMagic()` | Lấy magic number trong yêu cầu giao dịch gần nhất |
| `RequestOrder()` | Lấy ticket lệnh trong yêu cầu giao dịch gần nhất |
| `RequestSymbol()` | Lấy tên symbol sử dụng trong yêu cầu giao dịch gần nhất |
| `RequestVolume()` | Lấy khối lượng giao dịch (lots) trong yêu cầu gần nhất |
| `RequestPrice()` | Lấy mức giá trong yêu cầu gần nhất |
| `RequestStopLimit()` | Lấy giá kích hoạt của lệnh Stop Limit trong yêu cầu gần nhất |
| `RequestSL()` | Lấy giá Stop Loss trong yêu cầu gần nhất |
| `RequestTP()` | Lấy giá Take Profit trong yêu cầu gần nhất |
| `RequestDeviation()` | Lấy độ lệch giá tối đa (slippage) trong yêu cầu gần nhất |
| `RequestType()` | Lấy loại yêu cầu/lệnh gần nhất |
| `RequestTypeDescription()` | Lấy mô tả dạng chuỗi của loại yêu cầu/lệnh gần nhất |
| `RequestTypeFilling()` | Lấy chế độ khớp lệnh trong yêu cầu gần nhất |
| `RequestTypeFillingDescription()` | Lấy mô tả dạng chuỗi của chế độ khớp lệnh trong yêu cầu gần nhất |
| `RequestTypeTime()` | Lấy thời hạn hiệu lực của lệnh trong yêu cầu gần nhất |
| `RequestTypeTimeDescription()` | Lấy mô tả dạng chuỗi của thời hạn hiệu lực của lệnh |
| `RequestExpiration()` | Lấy thời gian hết hạn trong yêu cầu gần nhất |
| `RequestComment()` | Lấy chuỗi comment trong yêu cầu gần nhất |
| `RequestPosition()` | Lấy ticket vị thế liên quan trong yêu cầu gần nhất |
| `RequestPositionBy()` | Lấy ticket vị thế đối ứng liên quan trong yêu cầu gần nhất |

### 6. Truy cập kết quả kiểm tra Yêu cầu giao dịch (Access to checking results)
| Tên Method | Mô tả |
| :--- | :--- |
| `CheckResult()` | Lấy bản sao cấu trúc kết quả kiểm tra yêu cầu (`MqlTradeCheckResult`) |
| `CheckResultRetcode()` | Lấy mã kết quả kiểm tra (retcode) |
| `CheckResultRetcodeDescription()` | Lấy mô tả dạng chuỗi của mã kết quả kiểm tra |
| `CheckResultBalance()` | Lấy số dư dự toán sau khi thực hiện yêu cầu giao dịch |
| `CheckResultEquity()` | Lấy tài sản dự toán (equity) sau khi thực hiện yêu cầu |
| `CheckResultProfit()` | Lấy lợi nhuận dự tính sau khi thực hiện yêu cầu |
| `CheckResultMargin()` | Lấy số tiền ký quỹ dự tính (margin) |
| `CheckResultMarginFree()` | Lấy số tiền ký quỹ miễn phí dự tính |
| `CheckResultMarginLevel()` | Lấy mức ký quỹ dự tính (margin level) |
| `CheckResultComment()` | Lấy comment trong kết quả kiểm tra |

### 7. Truy cập kết quả thực tế của Yêu cầu giao dịch (Access to execution results)
| Tên Method | Mô tả |
| :--- | :--- |
| `Result()` | Lấy bản sao cấu trúc kết quả giao dịch thực tế (`MqlTradeResult`) |
| `ResultRetcode()` | Lấy mã kết quả giao dịch thực tế (retcode) |
| `ResultRetcodeDescription()` | Lấy mô tả dạng chuỗi của mã kết quả giao dịch thực tế |
| `ResultDeal()` | Lấy ticket của deal được khớp thành công |
| `ResultOrder()` | Lấy ticket của order được tạo ra |
| `ResultVolume()` | Lấy khối lượng giao dịch được xác nhận bởi broker |
| `ResultPrice()` | Lấy mức giá được xác nhận bởi broker |
| `ResultBid()` | Lấy giá Bid hiện tại (nếu có requote) |
| `ResultAsk()` | Lấy giá Ask hiện tại (nếu có requote) |
| `ResultComment()` | Lấy chuỗi comment/phản hồi từ broker |

### 8. Phương thức hỗ trợ (Auxiliary methods)
| Tên Method | Mô tả |
| :--- | :--- |
| `PrintRequest()` | In toàn bộ tham số của yêu cầu gần nhất vào Journal log |
| `PrintResult()` | In toàn bộ kết quả của yêu cầu gần nhất vào Journal log |
| `FormatRequest(string text)` | Trả về chuỗi được định dạng chứa thông tin yêu cầu gần nhất |
| `FormatRequestResult(string text)` | Trả về chuỗi được định dạng chứa thông tin kết quả yêu cầu gần nhất |
