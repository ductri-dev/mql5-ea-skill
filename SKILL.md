---
name: mql5-ea
description: Use when writing, debugging, or reviewing MQL5 Expert Advisors, CTrade order logic, indicator handles, positions/orders, time-series arrays, or .mq5/.mqh include projects.
---

# MQL5 EA Coding Guide

## Overview
Guide cho MQL5 EA work: đúng API, an toàn indicator/trade handles, đúng time-series indexing, và tránh lỗi do nhầm MQL4/MQL5.

## When to Use
Use for `.mq5` / `.mqh` EA work: viết feature giao dịch/indicator/trailing/risk/news-time filter, debug compile/runtime, hoặc review `CTrade`, positions, pending orders, arrays, includes. Do not use for non-trading scripts or external strategy tuning/backtests.

## Core Pattern: New-Bar Candidate, Then Commit
Với logic chạy theo nến đóng, tách **phát hiện bar mới** khỏi **đánh dấu đã xử lý**. Commit bar sau khi dữ liệu `CopyBuffer()` / `CopyClose()` đã sẵn sàng để lỗi tải tạm thời không làm mất tín hiệu; nhưng nếu guard chủ động skip bar (`!IsTradeAllowed()`, `!IsMarketOpen()`, ngoài giờ trade), mark processed trước khi `return` để không trade lại tín hiệu cũ.

```diff
void OnTick() {
-  bool newBar = IsNewBar();       // cap nhat state qua som
-  if(!newBar) return;
-  if(CopyBuffer(h, 0, 0, 3, b) < 3) return; // mat bar neu loi tam thoi
+  datetime barTime = iTime(_Symbol, _Period, 0);
+  if(!IsNewBarCandidate(barTime)) return;
+  if(!IsTradeAllowed() || !IsMarketOpen()) { MarkBarProcessed(barTime); return; }
+  if(CopyBuffer(h, 0, 0, 3, b) < 3) return; // chua commit, tick sau retry
+  MarkBarProcessed(barTime);
   // logic...
}
```

`IsNewBarCandidate()`, `MarkBarProcessed()`, `IsTradeAllowed()`, `IsMarketOpen()`, `HasPosition()` không phải built-in MQL5; chỉ dùng khi EA đã có helper hoặc phải tự định nghĩa.

## Rules That Prevent Most EA Bugs
- Đọc EA hiện có trước: inputs, globals, magic/comment, helpers, event handlers, current trade flow. Nếu điều kiện entry/exit, risk, symbol/timeframe, hoặc xử lý khi đã có position chưa rõ, hỏi lại trước khi code.
- Chỉ mở reference liên quan ở bảng dưới. Nếu tạo EA mới, dùng [templates/ea_base.mq5](templates/ea_base.mq5). Trước khi bàn giao, chạy [references/pitfalls.md](references/pitfalls.md).
- Indicator functions (`iMA`, `iRSI`, `iCustom`) trả handle, không trả value. Tạo handle trong `OnInit()`, check `INVALID_HANDLE`, đọc bằng checked `CopyBuffer()`, release trong `OnDeinit()`.
- Positions: `PositionsTotal()` -> `PositionGetTicket(i)` -> `PositionSelectByTicket(ticket)` trước mọi `PositionGet*`. Pending orders: `OrdersTotal()` -> `OrderGetTicket(i)` auto-select order hiện tại; check ticket != 0 rồi filter `ORDER_MAGIC`, `ORDER_SYMBOL`, `ORDER_TYPE`.
- `CTrade` không có `trade.SetStopLoss()` / `trade.SetTakeProfit()`. SL/TP truyền vào `Buy()` / `Sell()` hoặc sửa bằng `PositionModify()`. Cấu hình magic/deviation/filling trong `OnInit()`; sau trade/modify/delete check bool và `trade.ResultRetcode()`.
- Thay `MarketInfo(sym, MODE_SPREAD)` bằng `SymbolInfoInteger(sym, SYMBOL_SPREAD)`. Dùng `_Digits` cho chart symbol, hoặc `SYMBOL_DIGITS` cho symbol khác.
- Tín hiệu nến đóng dùng `[1]` và `[2]`, tránh `[0]` để vào lệnh. Nếu code giả định `[0]` là bar hiện tại, `ArraySetAsSeries(arr, true)` cho mảng nhận `CopyXxx()` / `CopyBuffer()`.
- Với `.mq5 + .mqh`, global dùng trong class/member function của `.mqh` phải khai báo trong `.mqh`; file `.mqh` dùng lại nên có include guard. Đặt function dependencies trước chỗ gọi và tránh trùng tên helper/global.

## Quick Reference

| Need | Read |
|------|------|
| Indicator handles, `CopyBuffer`, `iCustom` | [references/indicators.md](references/indicators.md) |
| `CTrade`, Buy/Sell, retcode, SL/TP | [references/trading.md](references/trading.md) |
| Deal/order history, PnL, win/loss streak | [references/history.md](references/history.md) |
| Risk lot, volume normalize, `OrderCalcProfit` | [references/lotsize.md](references/lotsize.md) |
| Series arrays, `CopyRates`, `CopyClose` | [references/arrays.md](references/arrays.md) |
| Hours, sessions, weekdays, broker/GMT time | [references/time-filter.md](references/time-filter.md) |
| Close/modify positions, delete/count pending orders | [references/order-management.md](references/order-management.md) |
| Breakeven, R:R, points, EMA trailing | [references/trailing-sl.md](references/trailing-sl.md) |
| Economic Calendar news block | [references/news-block-trading.md](references/news-block-trading.md) |
| Final compile/runtime checklist | [references/pitfalls.md](references/pitfalls.md) |
