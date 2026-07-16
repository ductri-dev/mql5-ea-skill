# MQL5 Common Pitfalls — Checklist

Chạy checklist này trước khi finalize bất kỳ đoạn code EA nào.

---

## OnInit()

- [ ] Mọi indicator handle đều kiểm tra `== INVALID_HANDLE` và return `INIT_FAILED` nếu lỗi
- [ ] Mỗi handle được lưu vào biến global (không tạo handle inline trong OnTick)
- [ ] `CTrade` được set magic number và deviation
- [ ] `CTrade` dùng `SetTypeFillingBySymbol(_Symbol)` hoặc filling mode hợp lệ với symbol
- [ ] Biến global dùng trong `.mqh` được khai báo trong `.mqh`, không phải `.mq5`

---

## OnDeinit()

- [ ] **Mọi** handle được `IndicatorRelease()` — đếm số lần tạo handle = số lần release
- [ ] Sau release, gán lại `= INVALID_HANDLE` để tránh double-release
- [ ] Xóa chart objects nếu EA đã tạo (`ObjectsDeleteAll()` theo prefix hoặc `ObjectDelete()` từng object)

---

## Helper functions — PHẢI định nghĩa trong file EA

`IsTradeAllowed()`, `HasPosition()`, `IsNewBarCandidate()`, `MarkBarProcessed()`, `IsMarketOpen()` **không phải built-in MQL5**.
Khi viết EA mới, phải copy body của các hàm này vào cuối file — không dùng nếu chưa định nghĩa.

```mq5
// Bắt buộc có trong mọi EA — kiểm tra terminal, account và EA permission.
bool IsTradeAllowed()
{
   return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
          (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}
```

- [ ] `IsTradeAllowed()` đã được định nghĩa trong file
- [ ] `HasPosition()` đã được định nghĩa nếu dùng
- [ ] `IsNewBarCandidate()` / `MarkBarProcessed()` đã được định nghĩa nếu dùng logic nến mới
- [ ] `IsMarketOpen()` đã được định nghĩa nếu EA mở/đóng lệnh theo market
- [ ] `IsTradeRetcodeSuccess()` / `CheckTradeResult()` đã được định nghĩa nếu dùng `CTrade`

---

## OnTick() — trước khi trade

- [ ] `if(!IsTradeAllowed()) return;` hoặc mark bar processed rồi return nếu đang trong logic nến mới và muốn bỏ qua bar đó hẳn
- [ ] Kiểm tra `IsMarketOpen()` **riêng biệt** với `IsTradeAllowed()` — `IsTradeAllowed()` không phát hiện market closed (retcode `10018 TRADE_RETCODE_MARKET_CLOSED`)
- [ ] Mặc định: `if(!IsMarketOpen()) return;` — không cố vào/đóng lệnh khi market đóng. Chỉ implement `g_pendingSignal` khi user yêu cầu rõ ràng là cần giữ tín hiệu qua đóng cửa (xem cuối `trading.md`)
- [ ] Kiểm tra return value của mọi `CopyBuffer()` / `CopyRates()` / `CopyClose()`
- [ ] Mọi array dùng với CopyXxx / CopyBuffer đã `ArraySetAsSeries(arr, true)`
- [ ] Dùng `IsNewBarCandidate()` nếu logic chỉ cần chạy khi có bar mới (tránh spam orders)
- [ ] Với logic nến mới: **không commit bar trước khi data sẵn sàng**. Nếu `CopyBuffer()` / `CopyClose()` fail tạm thời, return mà chưa gọi `MarkBarProcessed()` để tick sau retry.
- [ ] Nếu guard chủ động bỏ qua bar (`!IsTradeAllowed()`, `!IsMarketOpen()`, ngoài giờ trade/news block và không lưu pending signal), gọi `MarkBarProcessed(barTime)` trước `return` để không trade lại tín hiệu cũ trong cùng bar.

```mq5
// SAI — commit bar qua som, CopyBuffer fail se lam mat tin hieu cua bar nay
void OnTick() {
   bool newBar = IsNewBar();           // lastBarTime da bi cap nhat
   if(!newBar) return;
   if(CopyBuffer(h, 0, 0, 3, buf) < 3) return; // tick sau newBar=false
}

// DUNG — detect truoc, commit sau khi data san sang hoac khi chu dong skip
void OnTick() {
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(!IsNewBarCandidate(barTime)) return;

   if(!IsTradeAllowed() || !IsMarketOpen()) {
      MarkBarProcessed(barTime);       // chu dong bo qua bar nay
      return;
   }

   if(CopyBuffer(h, 0, 0, 3, buf) < 3) return; // chua commit, tick sau retry
   MarkBarProcessed(barTime);          // data da san sang, tranh double execution

   // detect signal va trade...
}
```

- [ ] Nếu trade theo nến đóng: dùng `[1]` và `[2]`, không dùng `[0]` để xác nhận tín hiệu

---

## Giá và lot size

- [ ] Normalize mọi giá SL/TP trước khi trade: dùng `_Digits` cho chart symbol, hoặc `SYMBOL_DIGITS` cho symbol khác
- [ ] Lot size đã qua helper trong `lotsize.md`: clamp về [lotMin, lotMax], round theo `SYMBOL_VOLUME_STEP`
- [ ] SL/TP khoảng cách tối thiểu ≥ `SYMBOL_TRADE_STOPS_LEVEL` points
- [ ] Khi modify SL/TP, kiểm thêm `SYMBOL_TRADE_FREEZE_LEVEL` nếu giá gần vùng freeze

```mq5
int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
// SL phải cách giá entry ít nhất stopsLevel points
```

---

## Positions và orders

- [ ] Loop positions từ `PositionsTotal()-1` **xuống** 0 (tránh skip khi xóa trong loop)
- [ ] Filter theo `POSITION_MAGIC == InpMagicNumber` để không đụng position của EA khác
- [ ] Duyệt vị thế bằng `PositionGetTicket(i)` + `PositionSelectByTicket(ticket)` — không dùng `PositionGetSymbol(i)` để select ngầm. Luôn gọi `PositionSelectByTicket` trước mọi `PositionGet*`
- [ ] Kiểm tra cả return value và `trade.ResultRetcode()` của `trade.Buy()`, `trade.Sell()`, `trade.PositionModify()`
- [ ] Pending orders dùng `OrdersTotal()` -> `OrderGetTicket(i)` (auto-select), check `ticket != 0`, rồi filter theo `ORDER_MAGIC`, `ORDER_SYMBOL`, `ORDER_TYPE`

---

## Multi-file project

- [ ] Biến global dùng trong class member function của `.mqh` → khai báo trong `.mqh`
- [ ] Không khai báo biến trùng tên ở cả `.mq5` và `.mqh`
- [ ] `.mqh` dùng lại nhiều nơi có include guard (`#ifndef` / `#define` / `#endif`)

---

## Syntax — Các lỗi compile thường gặp

- [ ] `input group "..."` phải có dấu **`;`** ở cuối — thiếu là lỗi compile ngay

```mq5
// SAI
input group "=== Settings ==="
input double InpLot = 0.1;

// ĐÚNG
input group "=== Settings ===";
input double InpLot = 0.1;
```

---

## Lỗi phổ biến — quick reference

| Triệu chứng | Nguyên nhân thường gặp |
|---|---|
| Handle = -1 (INVALID_HANDLE) | Symbol/period sai, hoặc symbol chưa subscribe trong Market Watch |
| CopyBuffer trả -1 | Handle invalid, hoặc chưa đủ history bars |
| "undeclared identifier" ở `.mq5` | Biến khai báo sau `#include` nhưng dùng trong `.mqh` |
| SL/TP bị reject (`TRADE_RETCODE_INVALID_STOPS`) | Khoảng cách < `SYMBOL_TRADE_STOPS_LEVEL`, nằm trong freeze level, hoặc quên normalize price |
| Order bị requote (`TRADE_RETCODE_REQUOTE`) | Deviation quá thấp, tăng `SetDeviationInPoints` hoặc refresh tick |
| EA trade cả position của EA khác | Quên filter theo POSITION_MAGIC |
| Array index out of range | CopyBuffer trả ít hơn số phần tử yêu cầu, không kiểm tra return value |
| bar[0] là bar cũ (logic ngược) | Quên `ArraySetAsSeries(arr, true)` |
| Tín hiệu repaint trên bar mới | Dùng `[0]` để trade thay vì nến đã đóng `[1]` |
| Compile error gần dòng `input group` | Thiếu dấu `;` sau chuỗi tên group |
| `retcode 10018` (market closed), trade fail dù `IsTradeAllowed()` = true | Thiếu `IsMarketOpen()` check; mặc định return sớm khi market đóng |
