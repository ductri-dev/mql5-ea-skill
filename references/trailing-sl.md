# Trailing Stop Loss — 4 Kỹ Thuật Chuẩn MQL5

## Tổng Quan

Trailing SL dời Stop Loss tự động theo hướng có lợi, giúp "khóa" lợi nhuận mà không cần canh màn hình. Có 4 phương pháp phổ biến:

| # | Tên | Dùng khi |
|---|-----|----------|
| 1 | Breakeven | Luôn kết hợp với các phương pháp khác để loại bỏ rủi ro gốc |
| 2 | Trailing R:R | Swing trading, chiến lược dựa trên bội số R |
| 3 | Trailing Points | Trend-following, thị trường xu hướng mạnh |
| 4 | Trailing EMA | Hệ thống dùng EMA làm bộ lọc xu hướng |

---

## Nguyên Tắc Chung (Áp Dụng Cho Mọi Phương Pháp)

Các snippet dưới đây phụ thuộc `CheckTradeResult()` trong `trading.md`; không gọi `trade.PositionModify()` trần vì cần kiểm tra cả `ResultRetcode()`.

### Validate trước khi Modify

Luôn kiểm tra `SYMBOL_TRADE_STOPS_LEVEL` và `SYMBOL_TRADE_FREEZE_LEVEL` trước khi gọi `PositionModify()`:

```mq5
int GetModifyDistancePoints()
{
    int stopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    return (int)MathMax(stopsLevel, freezeLevel);
}

bool IsValidStopForPosition(ENUM_POSITION_TYPE type, double slPrice, double bid, double ask)
{
    double minDistance = GetModifyDistancePoints() * _Point;
    if (type == POSITION_TYPE_BUY)
        return (slPrice < bid && (bid - slPrice) >= minDistance);
    if (type == POSITION_TYPE_SELL)
        return (slPrice > ask && (slPrice - ask) >= minDistance);
    return false;
}
```

### Loop duyệt lệnh — Filter đúng thứ tự

```mq5
for (int i = PositionsTotal() - 1; i >= 0; i--)
{
    ulong ticket = PositionGetTicket(i);
    if (!PositionSelectByTicket(ticket)) continue;
    if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
    if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
    // ... xử lý
}
```

### SL chỉ dời theo hướng có lợi — không bao giờ lùi lại

- BUY:  `newSL > currentSL` → mới Modify
- SELL: `currentSL == 0 || newSL < currentSL` → mới Modify

---

## Phương Pháp 1: Breakeven

**Ý tưởng:** Khi giá đi được `InpBreakevenTrigger` points, dời SL về đúng entry price. Rủi ro gốc gần như bằng 0.

```
BUY:  (bid - entry) >= trigger && currentSL < entry  → SL = entry
SELL: (entry - ask) >= trigger && currentSL > entry  → SL = entry
```

**Code:**

```mq5
void MoveToBreakeven()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double tp        = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if (type == POSITION_TYPE_BUY)
        {
            if ((bid - openPrice) / _Point >= InpBreakevenTrigger && currentSL < openPrice)
            {
                if (!IsValidStopForPosition(type, openPrice, bid, ask)) continue;
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, openPrice, tp));
            }
        }
        else if (type == POSITION_TYPE_SELL)
        {
            if ((openPrice - ask) / _Point >= InpBreakevenTrigger
                && (currentSL == 0 || currentSL > openPrice))
            {
                if (!IsValidStopForPosition(type, openPrice, bid, ask)) continue;
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, openPrice, tp));
            }
        }
    }
}
```

**Lưu ý:**
- Thường dùng kết hợp: Breakeven khi đạt 1R, sau đó bật Trailing Points/EMA.
- Có TakeProfit vì không có cơ chế chốt lệnh nào khác.

---

## Phương Pháp 2: Trailing Theo R:R

**Ý tưởng:** 1R = `InpStopLoss` points. Mỗi lần giá đi thêm 1R, dời SL lên 1R:

```
Giá đi 1R → SL về entry (bảo vệ vốn)
Giá đi 2R → SL về +1R
Giá đi 3R → SL về +2R
```

**Công thức:**

```mq5
int    rMultiple = (int)(distanceFromOpen / oneR);   // bội số R hiện tại
double newSL     = entry ± (rMultiple - 1) * oneR * _Point;
```

**Code:**

```mq5
void TrailingStopByRiskReward()
{
    double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double oneR = (double)InpStopLoss;

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double tp        = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if (type == POSITION_TYPE_BUY)
        {
            double dist = (bid - openPrice) / _Point;
            int    rMul = (int)(dist / oneR);
            if (rMul < 1) continue;

            double newSL = NormalizeDouble(openPrice + (rMul - 1) * oneR * _Point, _Digits);
            if (newSL > currentSL && IsValidStopForPosition(type, newSL, bid, ask))
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, newSL, tp));
        }
        else if (type == POSITION_TYPE_SELL)
        {
            double dist = (openPrice - ask) / _Point;
            int    rMul = (int)(dist / oneR);
            if (rMul < 1) continue;

            double newSL = NormalizeDouble(openPrice - (rMul - 1) * oneR * _Point, _Digits);
            if ((currentSL == 0 || newSL < currentSL) && IsValidStopForPosition(type, newSL, bid, ask))
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, newSL, tp));
        }
    }
}
```

**Ưu / Nhược:**
- Ưu: Lợi nhuận được "khóa" theo bội số R rõ ràng, dễ backtest.
- Nhược: Bước dời cứng nhắc (nhảy từng R), không bắt được đỉnh tốt nhất.
- Không dùng TakeProfit — Trailing SL là cơ chế chốt lệnh duy nhất.

---

## Phương Pháp 3: Trailing Theo Points (Khoảng Cách Cố Định)

**Ý tưởng:**
1. Chờ giá đi được `InpTrailingStart` points → bắt đầu trailing.
2. SL luôn cách giá hiện tại đúng `InpTrailingDistance` points.
3. Giá đảo chiều → SL **giữ nguyên**, không lùi lại.

```
BUY:  newSL = bid - InpTrailingDistance * _Point
SELL: newSL = ask + InpTrailingDistance * _Point
```

**Code:**

```mq5
void TrailingStopByPoints()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double tp        = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if (type == POSITION_TYPE_BUY)
        {
            if ((bid - openPrice) / _Point < InpTrailingStart) continue;
            double newSL = NormalizeDouble(bid - InpTrailingDistance * _Point, _Digits);
            if (newSL > currentSL && IsValidStopForPosition(type, newSL, bid, ask))
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, newSL, tp));
        }
        else if (type == POSITION_TYPE_SELL)
        {
            if ((openPrice - ask) / _Point < InpTrailingStart) continue;
            double newSL = NormalizeDouble(ask + InpTrailingDistance * _Point, _Digits);
            if ((currentSL == 0 || newSL < currentSL) && IsValidStopForPosition(type, newSL, bid, ask))
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, newSL, tp));
        }
    }
}
```

**Ưu / Nhược:**
- Ưu: Linh hoạt, bắt được đỉnh thực tế của trend, chạy mỗi tick.
- Nhược: Nhạy với noise — `TrailingDistance` quá nhỏ dễ bị hit sớm trong thị trường sideway.
- Quy tắc chọn `TrailingDistance`: thường >= ATR(14) để tránh noise.

---

## Phương Pháp 4: Trailing Theo EMA (Hoặc Indicator Khác)

**Ý tưởng:**
- SL = giá trị EMA tại nến đã đóng (index `[1]`).
- BUY:  `emaValue > currentSL` → dời SL lên.
- SELL: `emaValue < currentSL` → dời SL xuống.
- Giá đảo chiều thì SL đứng yên.

**Khởi tạo handle (trong `OnInit`):**

```mq5
int handleEMA = INVALID_HANDLE;
double emaBuffer[];

handleEMA = iMA(_Symbol, InpEMATimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
if (handleEMA == INVALID_HANDLE)
{
    Print("Không tạo được EMA handle");
    return INIT_FAILED;
}
ArraySetAsSeries(emaBuffer, true);
```

**Release trong `OnDeinit`:**

```mq5
if (handleEMA != INVALID_HANDLE) IndicatorRelease(handleEMA);
```

**Đọc giá trị EMA (dùng index [1] — nến đã đóng):**

```mq5
bool GetEMAValue(double &emaValue)
{
    if (CopyBuffer(handleEMA, 0, 0, 3, emaBuffer) < 3) return false;
    emaValue = emaBuffer[1];
    return true;
}
```

**Trailing SL theo EMA:**

```mq5
void TrailingStopByEMA(double emaValue)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        double currentSL = PositionGetDouble(POSITION_SL);
        double tp        = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        double newSL = NormalizeDouble(emaValue, _Digits);

        if (type == POSITION_TYPE_BUY)
        {
            if (newSL > currentSL && IsValidStopForPosition(type, newSL, bid, ask))
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, newSL, tp));
        }
        else if (type == POSITION_TYPE_SELL)
        {
            if ((currentSL == 0 || newSL < currentSL) && IsValidStopForPosition(type, newSL, bid, ask))
                CheckTradeResult("PositionModify", trade.PositionModify(ticket, newSL, tp));
        }
    }
}
```

**Gọi trong `OnTick`:**

```mq5
double emaValue;
if (GetEMAValue(emaValue)) TrailingStopByEMA(emaValue);
```

**Ưu / Nhược:**
- Ưu: SL bám theo xu hướng tự nhiên, ít noise hơn trailing points.
- Nhược: Phụ thuộc chu kỳ EMA — chọn sai period thì kém hiệu quả.
- Có thể thay EMA bằng bất kỳ indicator nào khác (ATR, Bollinger, Supertrend...) bằng cách đổi handle và đọc buffer tương ứng.

---

## Pitfalls Hay Gặp

| Lỗi | Nguyên nhân | Fix |
|-----|-------------|-----|
| Modify liên tục mỗi tick dù SL không đổi | Không check `newSL > currentSL` | Thêm guard `if (newSL <= currentSL) continue` |
| SL lùi lại khi giá đảo | Quên điều kiện một chiều | BUY: `newSL > currentSL`; SELL: `newSL < currentSL` |
| Error 4756 / 130 khi Modify | SL quá gần giá (< stops level) | Dùng `IsValidStopForPosition()` trước mỗi lần Modify |
| EMA trả giá trị nến đang hình thành | Dùng buffer `[0]` | Luôn dùng `[1]` (nến đã đóng) cho tín hiệu |
| Memory leak indicator | Không gọi `IndicatorRelease` trong `OnDeinit` | Release tất cả handles trong `OnDeinit` |
| SELL Breakeven không trigger | `currentSL == 0` khi broker set SL = 0 mặc định | Check `currentSL == 0 \|\| currentSL > openPrice` |

---

## Kết Hợp Nhiều Phương Pháp

Breakeven thường được kết hợp với phương pháp khác:

```
Khi giá đi 1R  → Breakeven (loại bỏ rủi ro)
Khi giá đi 2R+ → Trailing Points / EMA (bắt thêm profit)
```

Trong `OnTick`, gọi cả hai hàm mỗi tick — thứ tự không quan trọng vì mỗi hàm đều có guard riêng:

```mq5
MoveToBreakeven();
TrailingStopByPoints();
```
