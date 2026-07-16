# MQL5 Snippet — Order Management

Các hàm quản lý vị thế đang mở theo pattern 3 bước:
1. **BƯỚC 1:** Duyệt tất cả lệnh đang mở từ cuối về đầu.
2. **BƯỚC 2:** Filter lệnh cần xử lý.
3. **BƯỚC 3:** Thực hiện hành động.

**Setup bắt buộc trong EA (thêm vào đầu file và khai báo global):**
```mql5
#include <Trade\Trade.mqh>
CTrade trade;
```

**Dependency chung:** paste `IsTradeAllowed` một lần từ `trading.md`.

---

### Ghi chú mở rộng BƯỚC 3
**Mục đích:** Khi có yêu cầu quản lý lệnh mới, giữ nguyên pattern 3 bước và chỉ thay action ở **BƯỚC 3**.

- Với **vị thế đang mở** (`PositionsTotal`, `PositionGetTicket`, `PositionSelectByTicket`):
  - Dùng `trade.PositionClose(ticket)` khi action là đóng toàn bộ vị thế.
  - Dùng `trade.PositionModify(ticket, sl, tp)` khi action là sửa SL/TP, trailing stop, hoặc dời về breakeven. Giữ giá trị SL/TP cũ nếu không muốn thay đổi phía đó.
  - Dùng `trade.PositionClosePartial(ticket, volume)` khi action là đóng một phần vị thế. Ưu tiên overload theo `ticket` khi đang duyệt từng vị thế; chuẩn hóa `volume` theo lot step và kiểm tra account có hỗ trợ hedging nếu chiến lược phụ thuộc partial close theo từng ticket.
- Với **lệnh chờ** (`OrdersTotal`, `OrderGetTicket`):
  - `OrderGetTicket(i)` tự select order tại index `i`; check `ticket != 0` trước khi đọc `OrderGet*`.
  - Dùng `trade.OrderModify(ticket, price, sl, tp, type_time, expiration, stoplimit)` khi action là sửa giá vào lệnh, SL/TP, expiration, hoặc stop-limit price của pending order.
  - Dùng `trade.OrderDelete(ticket)` khi action là xóa pending order.
- Sau mọi action bằng `CTrade`, không chỉ dựa vào `bool` trả về. Luôn kiểm tra `trade.ResultRetcode()` vì `true` chỉ xác nhận request pass check cơ bản, chưa chắc trade server đã thực thi thành công. Xem `IsTradeRetcodeSuccess()` trong `trading.md`.
- Khi thêm helper mới cho pending orders, tách riêng helper với tên rõ ràng như `_ModifyOrdersByFilter` hoặc `_DeleteOrdersByFilter` thay vì trộn chung với `_ClosePositionsByFilter`.

Tài liệu MQL5 liên quan:
- `PositionModify`: https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionmodify
- `PositionClosePartial`: https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclosepartial
- `OrderModify`: https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradeordermodify
- `OrderDelete`: https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradeorderdelete

---

### ENUM_POSITION_PROFIT_FILTER
**Mục đích:** Chọn cách lọc lệnh theo trạng thái lãi/lỗ.
**Phụ thuộc:** không có

```mql5
enum ENUM_POSITION_PROFIT_FILTER
{
   POSITION_PROFIT_FILTER_ANY         = 0,
   POSITION_PROFIT_FILTER_PROFIT_ONLY = 1,
   POSITION_PROFIT_FILTER_LOSS_ONLY   = -1
};
```

---

### _ClosePositionsByFilter *(internal helper)*
**Mục đích:** Helper dùng chung để đóng vị thế theo filter symbol, magic, type, profit và comment.
**Tham số:**
- `symbol` — symbol cần lọc, `""` = mọi symbol
- `filterMagic` — true = lọc theo `magicNumber`, false = bỏ qua magic
- `magicNumber` — magic number cần lọc khi `filterMagic=true`
- `positionType` — `(int)POSITION_TYPE_BUY`, `(int)POSITION_TYPE_SELL`, hoặc `-1` = mọi loại
- `profitFilter` — lọc mọi lệnh, chỉ lệnh lãi, hoặc chỉ lệnh lỗ
- `comment` — comment cần lọc, `""` = mọi comment
**Trả về:** `bool` — false nếu trading không được phép hoặc có ít nhất một lệnh đóng thất bại
**Phụ thuộc:** `IsTradeAllowed`, `CTrade trade`

```mql5
bool _ClosePositionsByFilter(string symbol,
                             bool filterMagic,
                             long magicNumber,
                             int positionType,
                             ENUM_POSITION_PROFIT_FILTER profitFilter,
                             string comment)
{
   if(!IsTradeAllowed()) return false;

   bool success = true;

   // BƯỚC 1: Duyệt từ cuối về đầu để thao tác đóng không làm lệch index.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;

      // BƯỚC 2: Filter theo symbol, magic, loại lệnh, profit và comment.
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(filterMagic && PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      if(positionType >= 0 && PositionGetInteger(POSITION_TYPE) != positionType) continue;
      if(comment != "" && PositionGetString(POSITION_COMMENT) != comment) continue;

      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profitFilter == POSITION_PROFIT_FILTER_PROFIT_ONLY && profit <= 0) continue;
      if(profitFilter == POSITION_PROFIT_FILTER_LOSS_ONLY   && profit >  0) continue;

      // BƯỚC 3: Đóng lệnh đã qua filter — kiểm tra ResultRetcode(), không dùng bool.
      bool sent    = trade.PositionClose(ticket);
      uint retcode = trade.ResultRetcode();
      bool ok = sent && (retcode == TRADE_RETCODE_DONE ||
                         retcode == TRADE_RETCODE_DONE_PARTIAL ||
                         retcode == TRADE_RETCODE_PLACED);
      if(!ok)
      {
         PrintFormat("PositionClose failed #%I64u: retcode=%u (%s)",
                     ticket, retcode, trade.ResultRetcodeDescription());
         success = false;
      }
   }
   return success;
}
```

---

### CloseCurrentSymbolPositions
**Mục đích:** Đóng tất cả vị thế của EA hiện tại trên `_Symbol`.
**Tham số:** `magicNumber`
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseCurrentSymbolPositions(ulong magicNumber)
{
   return _ClosePositionsByFilter(_Symbol, true, (long)magicNumber, -1, POSITION_PROFIT_FILTER_ANY, "");
}
```

---

### CloseAllPositions
**Mục đích:** Đóng tất cả vị thế khớp symbol + magic + comment. `symbol=""` = mọi symbol, `magicNumber=0` = mọi magic, `comment=""` = mọi comment.
**Tham số:** `symbol`, `magicNumber`, `comment`
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllPositions(string symbol, ulong magicNumber, string comment = "")
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, -1, POSITION_PROFIT_FILTER_ANY, comment);
}
```

---

### CloseAllBuyPositions
**Mục đích:** Đóng tất cả vị thế Buy theo symbol + magic. `symbol=""` = mọi symbol, `magicNumber=0` = mọi magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllBuyPositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, (int)POSITION_TYPE_BUY, POSITION_PROFIT_FILTER_ANY, "");
}
```

---

### CloseAllSellPositions
**Mục đích:** Đóng tất cả vị thế Sell theo symbol + magic. `symbol=""` = mọi symbol, `magicNumber=0` = mọi magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllSellPositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, (int)POSITION_TYPE_SELL, POSITION_PROFIT_FILTER_ANY, "");
}
```

---

### CloseAllProfitablePositions
**Mục đích:** Đóng tất cả vị thế đang lãi (`POSITION_PROFIT > 0`) theo symbol + magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllProfitablePositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, -1, POSITION_PROFIT_FILTER_PROFIT_ONLY, "");
}
```

---

### CloseAllProfitableBuyPositions
**Mục đích:** Đóng tất cả vị thế Buy đang lãi (`POSITION_PROFIT > 0`) theo symbol + magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllProfitableBuyPositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, (int)POSITION_TYPE_BUY, POSITION_PROFIT_FILTER_PROFIT_ONLY, "");
}
```

---

### CloseAllProfitableSellPositions
**Mục đích:** Đóng tất cả vị thế Sell đang lãi (`POSITION_PROFIT > 0`) theo symbol + magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllProfitableSellPositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, (int)POSITION_TYPE_SELL, POSITION_PROFIT_FILTER_PROFIT_ONLY, "");
}
```

---

### CloseAllLossPositions
**Mục đích:** Đóng tất cả vị thế đang lỗ hoặc hòa vốn (`POSITION_PROFIT <= 0`) theo symbol + magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllLossPositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, -1, POSITION_PROFIT_FILTER_LOSS_ONLY, "");
}
```

---

### CloseAllLossBuyPositions
**Mục đích:** Đóng tất cả vị thế Buy đang lỗ hoặc hòa vốn (`POSITION_PROFIT <= 0`) theo symbol + magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllLossBuyPositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, (int)POSITION_TYPE_BUY, POSITION_PROFIT_FILTER_LOSS_ONLY, "");
}
```

---

### CloseAllLossSellPositions
**Mục đích:** Đóng tất cả vị thế Sell đang lỗ hoặc hòa vốn (`POSITION_PROFIT <= 0`) theo symbol + magic.
**Trả về:** `bool`
**Phụ thuộc:** `_ClosePositionsByFilter`

```mql5
bool CloseAllLossSellPositions(string symbol, ulong magicNumber)
{
   return _ClosePositionsByFilter(symbol, magicNumber > 0, (long)magicNumber, (int)POSITION_TYPE_SELL, POSITION_PROFIT_FILTER_LOSS_ONLY, "");
}
```

---

## Pending Order Management

Các hàm xóa hàng loạt, đếm, và báo cáo lệnh chờ.
**Dependency:** `IsTradeAllowed` từ `trading.md`; `DeletePendingOrderByTicket` từ `trading.md`.

---

### DeleteAllPendingOrders
**Mục đích:** Xóa tất cả lệnh chờ theo symbol + magic. `symbol=""` = mọi symbol, `magicNumber=0` = mọi magic.
**Phụ thuộc:** `IsTradeAllowed`, `DeletePendingOrderByTicket`

```mql5
bool DeleteAllPendingOrders(string symbol, ulong magicNumber)
{
   if(!IsTradeAllowed()) return false;
   bool success = true;

   for(int x = OrdersTotal() - 1; x >= 0; x--)
   {
      ulong  ticket    = OrderGetTicket(x);
      if(ticket == 0) continue;

      string selSymbol = OrderGetString(ORDER_SYMBOL);
      ulong  selMagic  = (ulong)OrderGetInteger(ORDER_MAGIC);
      if(symbol != "" && symbol != selSymbol) continue;
      if(magicNumber != 0 && selMagic != magicNumber) continue;

      if(!DeletePendingOrderByTicket(ticket))
         success = false;
   }
   return success;
}
```

---

### _DeletePendingOrdersByType *(internal helper)*
**Mục đích:** Xóa lệnh chờ theo loại cụ thể. Dùng cho các wrapper Delete*Stop/Limit.
**Phụ thuộc:** `IsTradeAllowed`, `DeletePendingOrderByTicket`

```mql5
bool _DeletePendingOrdersByType(string symbol, ulong magicNumber, ENUM_ORDER_TYPE orderType)
{
   if(!IsTradeAllowed()) return false;
   bool success = true;

   for(int x = OrdersTotal() - 1; x >= 0; x--)
   {
      ulong ticket = OrderGetTicket(x);
      if(ticket == 0) continue;

      if(symbol != "" && OrderGetString(ORDER_SYMBOL) != symbol) continue;
      if(OrderGetInteger(ORDER_TYPE) != orderType) continue;
      if(magicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != magicNumber) continue;

      if(!DeletePendingOrderByTicket(ticket))
         success = false;
   }
   return success;
}

bool DeleteAllBuyStops(string symbol, ulong magicNumber)   { return _DeletePendingOrdersByType(symbol, magicNumber, ORDER_TYPE_BUY_STOP);   }
bool DeleteAllBuyLimits(string symbol, ulong magicNumber)  { return _DeletePendingOrdersByType(symbol, magicNumber, ORDER_TYPE_BUY_LIMIT);  }
bool DeleteAllSellStops(string symbol, ulong magicNumber)  { return _DeletePendingOrdersByType(symbol, magicNumber, ORDER_TYPE_SELL_STOP);  }
bool DeleteAllSellLimits(string symbol, ulong magicNumber) { return _DeletePendingOrdersByType(symbol, magicNumber, ORDER_TYPE_SELL_LIMIT); }
```

---

### _ScanPendingOrders *(internal helper)*
**Mục đích:** Quét lệnh chờ và đếm theo loại, filter theo symbol + magic. Dùng cho count helpers bên dưới.

```mql5
void _ScanPendingOrders(string symbol, ulong magicNumber,
                        int &buyStopCount, int &buyLimitCount,
                        int &sellStopCount, int &sellLimitCount)
{
   buyStopCount = 0; buyLimitCount = 0; sellStopCount = 0; sellLimitCount = 0;

   for(int x = 0; x < OrdersTotal(); x++)
   {
      ulong ticket = OrderGetTicket(x);
      if(ticket == 0) continue;
      if(symbol != "" && OrderGetString(ORDER_SYMBOL) != symbol) continue;
      if(magicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != magicNumber) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP)   buyStopCount++;
      if(type == ORDER_TYPE_BUY_LIMIT)  buyLimitCount++;
      if(type == ORDER_TYPE_SELL_STOP)  sellStopCount++;
      if(type == ORDER_TYPE_SELL_LIMIT) sellLimitCount++;
   }
}
```

---

### Order count helpers

```mql5
int SymbolOrdersTotal(string symbol, ulong magicNumber)
{
   int count = 0;
   for(int x = 0; x < OrdersTotal(); x++)
   {
      ulong ticket = OrderGetTicket(x);
      if(ticket == 0) continue;

      if(symbol != "" && OrderGetString(ORDER_SYMBOL) != symbol) continue;
      if(magicNumber != 0 && (ulong)OrderGetInteger(ORDER_MAGIC) != magicNumber) continue;
      count++;
   }
   return count;
}

int MagicOrdersTotal(ulong magicNumber)
{
   int count = 0;
   for(int x = 0; x < OrdersTotal(); x++)
   {
      ulong ticket = OrderGetTicket(x);
      if(ticket == 0) continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC) == magicNumber) count++;
   }
   return count;
}

int BuyStopOrdersTotal()   { int bs,bl,ss,sl; _ScanPendingOrders("",0,bs,bl,ss,sl); return bs; }
int BuyLimitOrdersTotal()  { int bs,bl,ss,sl; _ScanPendingOrders("",0,bs,bl,ss,sl); return bl; }
int SellStopOrdersTotal()  { int bs,bl,ss,sl; _ScanPendingOrders("",0,bs,bl,ss,sl); return ss; }
int SellLimitOrdersTotal() { int bs,bl,ss,sl; _ScanPendingOrders("",0,bs,bl,ss,sl); return sl; }

```

---

## Kiểm tra và đếm positions

> **Quy tắc bắt buộc khi duyệt danh sách vị thế:** Luôn dùng `PositionGetTicket(i)` + `PositionSelectByTicket(ticket)`. Gọi `PositionSelectByTicket` trước mọi `PositionGet*`.

```mql5
int CountPositions(const string symbol, const long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      count++;
   }
   return count;
}

bool HasPosition(const string symbol, const long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      return true;
   }
   return false;
}
```

---

## Đọc thông tin position đang mở

```mql5
for(int i = PositionsTotal() - 1; i >= 0; i--)
{
   ulong ticket = PositionGetTicket(i);
   if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
   if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double profit    = PositionGetDouble(POSITION_PROFIT);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
}
```

---

## Modify SL/TP của position đang mở

```mql5
if(PositionSelectByTicket(ticket))
{
   string symbol = PositionGetString(POSITION_SYMBOL);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double newSL = NormalizeDouble(newSlValue, digits);
   double newTP = NormalizeDouble(newTpValue, digits);

   CheckTradeResult("PositionModify",
                    trade.PositionModify(ticket, newSL, newTP));
}
```

Trước khi modify, kiểm tra `SYMBOL_TRADE_STOPS_LEVEL` và `SYMBOL_TRADE_FREEZE_LEVEL` nếu SL/TP gần giá hiện tại.

---

## Đóng position

```mql5
// Đóng theo ticket
CheckTradeResult("PositionClose", trade.PositionClose(ticket));

// Đóng tất cả positions của EA trên symbol hiện tại
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      CheckTradeResult("PositionClose", trade.PositionClose(ticket));
   }
}
```
