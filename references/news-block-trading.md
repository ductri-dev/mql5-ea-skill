# Chặn giao dịch ±N phút quanh tin tức (Economic Calendar Block)

## Ý tưởng cốt lõi

Trước và sau mỗi tin kinh tế quan trọng, thị trường thường biến động mạnh và spread nở rộng. EA cần tự động phát hiện các khung giờ nguy hiểm này và tạm dừng mở lệnh mới (hoặc đóng lệnh đang mở).

Cơ chế hoạt động:
1. Lấy danh sách tin từ `CalendarValueHistory()` → lọc theo quốc gia + mức độ quan trọng
2. Lưu thời gian các tin vào mảng `g_newsTimes[]`
3. Mỗi tick: kiểm tra xem `TimeTradeServer()` có nằm trong `[newsTime - block, newsTime + block]` không
4. Làm mới danh sách định kỳ (ví dụ mỗi 5 phút) để bắt được tin mới

---

## Inputs cần thiết

```mql5
input string                         InpCountryCode  = "US";    // Mã quốc gia ("US","EU","GB",... hoặc "" = tất cả)
input ENUM_CALENDAR_EVENT_IMPORTANCE InpImportance   = CALENDAR_IMPORTANCE_HIGH;
input int                            InpHours        = 24;       // Phạm vi lấy tin (giờ tính từ hiện tại)
input int                            InpBlockMinutes = 30;       // Số phút chặn trước/sau tin
```

---

## Global state

```mql5
datetime g_newsTimes[];  // Thời gian các tin đã qua filter
datetime g_lastRefresh;  // Lần cuối làm mới danh sách
```

---

## Hàm RefreshNewsList()

Lấy tin từ calendar server, lọc theo mức độ quan trọng, lưu vào `g_newsTimes[]`.

```mql5
void RefreshNewsList()
{
    datetime now       = TimeTradeServer();
    int      blockSec  = (int)MathMax(InpBlockMinutes, 0) * 60;
    datetime from      = now - blockSec;
    datetime to        = now + InpHours * 3600;
    string   codeParam = (InpCountryCode == "") ? NULL : InpCountryCode;

    MqlCalendarValue values[];
    if (!CalendarValueHistory(values, from, to, codeParam))
    {
        Print("RefreshNewsList: Không lấy được dữ liệu.");
        return;
    }

    ArrayResize(g_newsTimes, 0);

    int total = ArraySize(values);
    for (int i = 0; i < total; i++)
    {
        MqlCalendarEvent event;
        if (!CalendarEventById(values[i].event_id, event)) continue;
        if (event.importance != InpImportance) continue;

        int n = ArraySize(g_newsTimes);
        ArrayResize(g_newsTimes, n + 1);
        g_newsTimes[n] = values[i].time;
    }

    g_lastRefresh = now;
    PrintFormat("RefreshNewsList: %d tin (country=%s | importance=%s)",
                ArraySize(g_newsTimes),
                (InpCountryCode == "") ? "TẤT CẢ" : InpCountryCode,
                EnumToString(InpImportance));
}
```

**Lưu ý:** `from` phải lùi về quá khứ ít nhất bằng `InpBlockMinutes`. Nếu query từ đúng `now`, một tin vừa xảy ra 5-10 phút trước sẽ không có trong `g_newsTimes[]`, dù EA vẫn đang nằm trong vùng cấm sau tin.

---

## Hàm IsNewsBlocked()

Kiểm tra xem thời điểm hiện tại có nằm trong vùng cấm không.

```mql5
bool IsNewsBlocked(datetime &nearestNews, int &secondsLeft)
{
    datetime now   = TimeTradeServer();
    int      block = InpBlockMinutes * 60;

    int n = ArraySize(g_newsTimes);
    for (int i = 0; i < n; i++)
    {
        datetime blockStart = g_newsTimes[i] - block;
        datetime blockEnd   = g_newsTimes[i] + block;

        if (now >= blockStart && now <= blockEnd)
        {
            nearestNews = g_newsTimes[i];
            secondsLeft = (int)(blockEnd - now);
            return true;
        }
    }

    nearestNews = 0;
    secondsLeft = 0;
    return false;
}
```

---

## Hàm SecondsToNextNews()

Tính số giây đến tin tiếp theo (dùng để log khi trạng thái OK).

```mql5
int SecondsToNextNews()
{
    datetime now  = TimeTradeServer();
    int      minS = INT_MAX;

    int n = ArraySize(g_newsTimes);
    for (int i = 0; i < n; i++)
    {
        int diff = (int)(g_newsTimes[i] - now);
        if (diff > 0 && diff < minS)
            minS = diff;
    }

    return (minS == INT_MAX) ? -1 : minS;
}
```

---

## OnInit()

Gọi `RefreshNewsList()` ngay khi khởi động và in lịch cấm ra journal.

```mql5
int OnInit()
{
    RefreshNewsList();

    int n = ArraySize(g_newsTimes);
    PrintFormat("--- Lịch cấm giao dịch (%d tin) ---", n);
    for (int i = 0; i < n; i++)
    {
        PrintFormat("  [%d] Tin lúc %s  |  Cấm: %s → %s",
                    i + 1,
                    TimeToString(g_newsTimes[i], TIME_DATE|TIME_MINUTES),
                    TimeToString(g_newsTimes[i] - InpBlockMinutes * 60, TIME_DATE|TIME_MINUTES),
                    TimeToString(g_newsTimes[i] + InpBlockMinutes * 60, TIME_DATE|TIME_MINUTES));
    }

    return INIT_SUCCEEDED;
}
```

---

## OnTick()

Làm mới danh sách định kỳ + kiểm tra trạng thái blocked. Chỉ log khi trạng thái **thay đổi** để tránh spam journal.

```mql5
void OnTick()
{
    // Làm mới mỗi 5 phút (300 giây)
    if (TimeTradeServer() - g_lastRefresh > 300)
        RefreshNewsList();

    datetime nearestNews;
    int      secondsLeft;
    bool     blocked = IsNewsBlocked(nearestNews, secondsLeft);

    static bool prevBlocked = false;
    if (blocked == prevBlocked) return;
    prevBlocked = blocked;

    if (blocked)
    {
        PrintFormat("[BLOCKED] Cấm giao dịch | Tin lúc %s | Còn %d phút %d giây",
                    TimeToString(nearestNews, TIME_DATE|TIME_MINUTES),
                    secondsLeft / 60, secondsLeft % 60);
        // TODO: đóng lệnh đang mở, tắt cờ cho phép mở lệnh mới, v.v.
    }
    else
    {
        int toNext = SecondsToNextNews();
        if (toNext > 0)
            PrintFormat("[OK] Có thể giao dịch | Tin tiếp theo sau %d phút %d giây",
                        toNext / 60, toNext % 60);
        else
            PrintFormat("[OK] Có thể giao dịch | Không còn tin nào trong %d giờ tới", InpHours);
    }
}
```

---

## Tích hợp vào EA thực tế

Thay vì chỉ log, gắn kết quả `IsNewsBlocked()` vào logic giao dịch:

```mql5
void OnTick()
{
    datetime barTime = iTime(_Symbol, _Period, 0);
    if (!IsNewBarCandidate(barTime)) return;

    if (TimeTradeServer() - g_lastRefresh > 300)
        RefreshNewsList();

    datetime nearestNews;
    int      secondsLeft;
    if (IsNewsBlocked(nearestNews, secondsLeft))
    {
        MarkBarProcessed(barTime); // chủ động bỏ qua bar này vì đang trong vùng cấm
        return;  // Bỏ qua toàn bộ logic giao dịch trong vùng cấm
    }

    // --- Logic giao dịch bình thường ---
    // Nếu CopyBuffer/CopyClose thất bại, return trước MarkBarProcessed(barTime) để retry.
    if (!ReadSignalData()) return; // placeholder: CopyBuffer/CopyClose/check dữ liệu

    MarkBarProcessed(barTime);
    // CheckSignal(), OpenTrade(), ManagePositions(), v.v.
}
```

---

## Các điểm cần lưu ý

| Vấn đề | Giải thích |
|--------|-----------|
| `CalendarValueHistory()` yêu cầu kết nối internet | Trong tester offline sẽ không có dữ liệu; dùng Strategy Tester với "Real ticks" + kết nối để test |
| `CalendarEventById()` có thể thất bại | Luôn kiểm tra giá trị trả về trước khi dùng `event.importance` |
| Múi giờ | `TimeTradeServer()` trả về giờ server broker, `CalendarValueHistory` cũng dùng cùng múi giờ — nhất quán |
| Tin bị thêm muộn | Broker có thể cập nhật lịch trễ; interval làm mới ngắn (5 phút) giúp bắt được tin mới |
| Nhiều tin liền nhau | Vùng cấm của các tin gần nhau có thể overlap — hàm `IsNewsBlocked()` xử lý đúng vì duyệt qua tất cả |

---

## Thứ tự quan trọng (`ENUM_CALENDAR_EVENT_IMPORTANCE`)

| Hằng số | Mô tả |
|---------|-------|
| `CALENDAR_IMPORTANCE_HIGH` | Cao (NFP, CPI, lãi suất...) |
| `CALENDAR_IMPORTANCE_MODERATE` | Trung bình |
| `CALENDAR_IMPORTANCE_LOW` | Thấp |
