# Chặn Vào Lệnh Theo Thời Gian (Time Filter)

## 1. Vấn đề múi giờ — cực kỳ quan trọng

`TimeCurrent()` trả về giờ **server broker**, không phải GMT+7.

```mq5
// Cách quy đổi sang giờ Việt Nam — luôn đi qua GMT, không đi qua broker
datetime vnTime = TimeGMT() + 7 * 3600;

// Kiểm tra offset của broker (chỉ để xác nhận cấu hình)
int offset = (int)(TimeCurrent() - TimeGMT()) / 3600;
```

Không cộng/trừ trực tiếp từ giờ broker vì broker còn thay đổi theo DST.

Broker phổ biến:
- IC Markets, Exness, XM → GMT+2 (mùa đông) / GMT+3 (mùa hè)
- FXCM → GMT+0

Pattern cho input `InpUseGMT` để user chọn lọc theo broker hay GMT:

```mq5
datetime GetReferenceNow()
{
    return InpUseGMT ? TimeGMT() : TimeCurrent();
}
```

---

## 2. Lọc theo khoảng giờ cụ thể (HH:mm)

### Parse chuỗi "HH:mm"

Input dạng chuỗi `"HH:mm"` dễ đọc, dễ chỉnh. Parse một lần trong `OnInit()`, lưu vào biến global.

```mq5
bool ParseHHMM(string hhmm, int &hour, int &minute)
{
    string parts[];
    int n = StringSplit(hhmm, ':', parts);
    if (n != 2) return false;

    hour   = (int)StringToInteger(parts[0]);
    minute = (int)StringToInteger(parts[1]);

    return (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59);
}
```

### Dựng datetime "hôm nay lúc HH:MM"

Kỹ thuật cốt lõi: lấy ngày từ `now`, ghi đè giờ/phút theo input.

```mq5
bool IsInTimeRange(datetime now)
{
    MqlDateTime dt;
    TimeToStruct(now, dt);

    dt.hour = g_startHour; dt.min = g_startMin; dt.sec = 0;
    datetime rangeStart = StructToTime(dt);

    dt.hour = g_endHour; dt.min = g_endMin; dt.sec = 0;
    datetime rangeEnd = StructToTime(dt);

    if (rangeStart <= rangeEnd)
        return (now >= rangeStart && now <= rangeEnd);   // cùng ngày
    return (now >= rangeStart || now <= rangeEnd);       // qua nửa đêm (vd 22:00 → 02:00)
}
```

**Lưu ý qua nửa đêm:** nếu `start > end` (vd `"22:00"` đến `"02:00"`) → dùng logic `||` thay vì `&&`.

---

## 3. Lọc theo phiên giao dịch

### Struct phiên

```mq5
struct TradingSession
{
    bool   enabled;
    string name;
    int    startHour;
    int    startMin;
    int    endHour;
    int    endMin;
};

TradingSession g_sessions[4];
```

### Kiểm tra một phiên

Logic giống `IsInTimeRange()` — dùng lại kỹ thuật dựng datetime "hôm nay lúc HH:MM":

```mq5
bool IsInSession(datetime now, const TradingSession &session)
{
    MqlDateTime dt;
    TimeToStruct(now, dt);

    dt.hour = session.startHour; dt.min = session.startMin; dt.sec = 0;
    datetime rangeStart = StructToTime(dt);

    dt.hour = session.endHour; dt.min = session.endMin; dt.sec = 0;
    datetime rangeEnd = StructToTime(dt);

    if (rangeStart <= rangeEnd)
        return (now >= rangeStart && now <= rangeEnd);
    return (now >= rangeStart || now <= rangeEnd);
}
```

### Kiểm tra bất kỳ phiên nào đang bật

```mq5
bool IsInAnyEnabledSession(datetime now, string &matchedName)
{
    for (int i = 0; i < 4; i++)
    {
        if (!g_sessions[i].enabled) continue;
        if (IsInSession(now, g_sessions[i]))
        {
            matchedName = g_sessions[i].name;
            return true;
        }
    }
    return false;
}
```

Giờ tham khảo các phiên (broker GMT+2, mùa đông):

| Phiên | Giờ broker |
|-------|-----------|
| Á (Tokyo) | 02:00 – 11:00 |
| Âu (London) | 10:00 – 19:00 |
| Mỹ (New York) | 15:00 – 00:00 |

Overlap Âu + Mỹ (15:00–19:00) — thanh khoản cao nhất.

---

## 4. Lọc theo ngày trong tuần

`MqlDateTime.day_of_week`: `0=Chủ Nhật, 1=T2, ..., 6=T7` (Unix convention — 0 là CN, không phải T2).

```mq5
bool IsDayAllowed(datetime now)
{
    MqlDateTime dt;
    TimeToStruct(now, dt);

    switch (dt.day_of_week)
    {
        case 0: return InpTradeOnSunday;
        case 1: return InpTradeOnMonday;
        case 2: return InpTradeOnTuesday;
        case 3: return InpTradeOnWednesday;
        case 4: return InpTradeOnThursday;
        case 5: return InpTradeOnFriday;
        case 6: return InpTradeOnSaturday;
    }
    return false;
}
```

Gợi ý thực tế:
- Thứ 2: hay có gap mở cửa → cân nhắc tắt
- Thứ 6 chiều: liquidity cạn trước weekend → cân nhắc tắt
- Thứ 7, CN: Forex gần đóng cửa → nên tắt

---

## 5. Kết hợp trong OnTick()

Đây là ví dụ minh họa — **không bắt buộc phải đủ cả 3 lớp**. Chọn một hoặc nhiều cách chặn và kết hợp tùy nhu cầu.

```mq5
void OnTick()
{
    datetime barTime = iTime(_Symbol, _Period, 0);
    if (!IsNewBarCandidate(barTime)) return;

    datetime now = GetReferenceNow();

    // Lớp tùy chọn: Lọc ngày trong tuần
    if (!IsDayAllowed(now))
    {
        if (InpClosePositionsOutsideTime) CloseAllOrders();
        MarkBarProcessed(barTime);
        return;
    }

    // Lớp tùy chọn: Lọc phiên giao dịch
    string matchedSession = "";
    if (!IsInAnyEnabledSession(now, matchedSession))
    {
        if (InpClosePositionsOutsideTime) CloseAllOrders();
        MarkBarProcessed(barTime);
        return;
    }

    // Lớp tùy chọn: Lọc khoảng giờ cụ thể
    if (!IsInTimeRange(now))
    {
        if (InpClosePositionsOutsideTime) CloseAllOrders();
        MarkBarProcessed(barTime);
        return;
    }

    // Trong khung giờ: đọc indicator/price trước. Nếu CopyBuffer/CopyClose lỗi,
    // return trước MarkBarProcessed(barTime) để tick sau retry.
    if (!ReadSignalData()) return; // placeholder: CopyBuffer/CopyClose/check dữ liệu

    MarkBarProcessed(barTime);
    CheckSignalAndTrade();
}
```

**Dùng 1 lớp:** chỉ gọi hàm chặn đó, bỏ qua các hàm còn lại.  
**Dùng 2 lớp:** kết hợp 2 hàm theo logic AND tùy ý.  
**Dùng cả 3:** như ví dụ trên.

---

## 6. Đóng lệnh ngoài giờ

"Lọc thời gian vào lệnh" (chặn lệnh mới) và "đóng lệnh ngoài giờ" là **hai hành vi khác nhau** — nên để thành input riêng biệt.

```mq5
input bool InpClosePositionsOutsideTime = false; // true = đóng position ngoài giờ

void CloseAllOrders()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        CheckTradeResult("PositionClose", trade.PositionClose(ticket));
    }
}
```

---

## 7. Checklist khi implement time filter

- [ ] Parse `HH:mm` trong `OnInit()`, return `INIT_PARAMETERS_INCORRECT` nếu sai định dạng
- [ ] Dùng `GetReferenceNow()` thống nhất — không gọi `TimeCurrent()` / `TimeGMT()` rải rác
- [ ] Xử lý range qua nửa đêm (logic `||` thay vì `&&`)
- [ ] Chặn lệnh mới và đóng lệnh là 2 input riêng biệt
- [ ] Nếu dùng logic nến mới, dùng `IsNewBarCandidate()` / `MarkBarProcessed()`; chỉ mark sau khi data sẵn sàng hoặc khi chủ động skip bar
- [ ] In cấu hình đã parse trong `OnInit()` để dễ debug trong Strategy Tester
