# MQL5 Truy Cập Lịch Sử Giao Dịch

Dùng file này khi cần đọc lệnh đã đóng, tính realized PnL, win rate, chuỗi thua liên tiếp, hoặc in chi tiết lịch sử khớp lệnh.

## Deal vs Order history

MT5 lưu lịch sử theo 2 lớp riêng biệt:

| Nhu cầu | Nhóm API |
|---|---|
| Lệnh đã khớp, realized PnL, commission, swap, entry/exit type | `HistoryDeals*` |
| Lệnh chờ đã hủy/hết hạn, metadata của order request | `HistoryOrders*` |

Để tính lãi/lỗ và win/loss, dùng `HistoryDeals*`. Lệnh đã đóng biến mất khỏi `PositionsTotal()` nhưng deal vẫn còn trong lịch sử.

## Trình tự bắt buộc — 4 bước chuẩn

Mỗi lần truy cập lịch sử, luôn đi theo 4 bước:

| Bước | Hành động |
|------|-----------|
| 1 — Load | `HistorySelect(from, to)` — **PHẢI gọi trước**, không thì `HistoryDealsTotal()` trả về 0 |
| 2 — Loop | Duyệt từng deal bằng `HistoryDealGetTicket(i)` |
| 3 — Filter | Lọc theo magic, symbol, entry type, deal type... |
| 4 — Action | Tính PnL, đếm win/loss, in log, quyết định lot... |

```mq5
datetime fromTime = TimeCurrent() - 7 * 24 * 3600;
datetime toTime   = TimeCurrent();

if(!HistorySelect(fromTime, toTime))
{
   Print("HistorySelect thất bại");
   return;
}

int totalDeals = HistoryDealsTotal();
for(int i = 0; i < totalDeals; i++)
{
   ulong dealTicket = HistoryDealGetTicket(i);
   if(dealTicket == 0) continue;

   // Đọc / lọc thuộc tính deal ở đây.
}
```

Nếu bỏ qua hoặc `HistorySelect()` thất bại, `HistoryDealsTotal()` có thể trả về `0` dù tài khoản có lịch sử.

## Hàm helper phổ biến

```mq5
datetime GetStartOfDay(datetime dt)
{
   return StringToTime(TimeToString(dt, TIME_DATE));
}

bool IsExitDealEntry(ENUM_DEAL_ENTRY dealEntry)
{
   return dealEntry == DEAL_ENTRY_OUT ||
          dealEntry == DEAL_ENTRY_INOUT ||
          dealEntry == DEAL_ENTRY_OUT_BY;
}

string DealEntryToText(ENUM_DEAL_ENTRY dealEntry)
{
   switch(dealEntry)
   {
      case DEAL_ENTRY_IN:     return "IN";
      case DEAL_ENTRY_OUT:    return "OUT";
      case DEAL_ENTRY_INOUT:  return "INOUT";
      case DEAL_ENTRY_OUT_BY: return "OUT_BY";
      default:                return "UNKNOWN";
   }
}
```

`DEAL_ENTRY_IN` mở/tăng vị thế. `DEAL_ENTRY_OUT`, `DEAL_ENTRY_INOUT`, và `DEAL_ENTRY_OUT_BY` là phía thoát lệnh — thường dùng để tính realized PnL.

## Thuộc tính deal cần đọc

| Thuộc tính | Hàm đọc | Ý nghĩa |
|---|---|---|
| `DEAL_TIME` | `HistoryDealGetInteger()` | Thời gian khớp lệnh |
| `DEAL_SYMBOL` | `HistoryDealGetString()` | Symbol |
| `DEAL_MAGIC` | `HistoryDealGetInteger()` | Magic number của EA |
| `DEAL_ENTRY` | `HistoryDealGetInteger()` | `IN`, `OUT`, `INOUT`, `OUT_BY` |
| `DEAL_TYPE` | `HistoryDealGetInteger()` | `DEAL_TYPE_BUY`, `DEAL_TYPE_SELL`... |
| `DEAL_VOLUME` | `HistoryDealGetDouble()` | Khối lượng khớp |
| `DEAL_PRICE` | `HistoryDealGetDouble()` | Giá khớp |
| `DEAL_PROFIT` | `HistoryDealGetDouble()` | Thành phần lãi/lỗ |
| `DEAL_COMMISSION` | `HistoryDealGetDouble()` | Thành phần commission |
| `DEAL_SWAP` | `HistoryDealGetDouble()` | Thành phần swap |
| `DEAL_POSITION_ID` | `HistoryDealGetInteger()` | ID vị thế — dùng để nhóm các deal cùng lệnh |

## Pattern lọc deal

Lọc chặt để một EA không đếm nhầm lệnh của EA khác.

```mq5
ulong dealMagic = (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
if(dealMagic != InpMagicNumber) continue;

string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
if(dealSymbol != _Symbol) continue;

ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
if(!IsExitDealEntry(entry)) continue;
```

Thêm filter `DEAL_TYPE` khi cần phân biệt hướng lệnh:

```mq5
ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
```

## Tính realized PnL theo khoảng thời gian

Duyệt deal thoát và cộng `DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP`.

```mq5
double CalcHistoryProfit(datetime fromTime,
                         datetime toTime,
                         ulong magicFilter,
                         bool allMagic)
{
   if(!HistorySelect(fromTime, toTime))
   {
      Print("HistorySelect thất bại");
      return 0.0;
   }

   double totalProfit = 0.0;
   int dealCount = 0;

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      ulong magic = (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(!allMagic && magic != magicFilter) continue;

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(symbol != _Symbol) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(!IsExitDealEntry(entry)) continue;

      double net = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP);

      totalProfit += net;
      dealCount++;
   }

   PrintFormat("Deals đóng=%d net=%.2f", dealCount, totalProfit);
   return totalProfit;
}
```

**Pitfall commission:** Nhiều broker ghi commission vào deal `DEAL_ENTRY_IN`, còn `DEAL_ENTRY_OUT` có `DEAL_COMMISSION == 0`. Nếu cần kết quả chính xác, cộng commission từ tất cả deal trong khoảng thời gian, hoặc nhóm theo `DEAL_POSITION_ID` để lấy đủ cả deal IN lẫn OUT của cùng một lệnh.

## Lợi nhuận deal đóng gần nhất

Dùng khi EA cần biết lệnh vừa đóng lãi hay lỗ trước khi chọn lot tiếp theo.

```mq5
double GetDealNetProfit(const ulong dealTicket)
{
   return HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
        + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
        + HistoryDealGetDouble(dealTicket, DEAL_SWAP);
}

double GetLastClosedDealNetProfit()
{
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   int totalDeals = HistoryDealsTotal();
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(!IsExitDealEntry(entry)) continue;

      return GetDealNetProfit(ticket);
   }

   return 0.0;
}
```

Hàm trả về net profit của deal thoát mới nhất theo symbol và magic hiện tại. Nếu `0.0` là kết quả có nghĩa trong chiến lược (breakeven), dùng output parameter kèm `bool` để phân biệt "không tìm thấy deal" với "deal breakeven".

## Tổng lỗ chuỗi thua liên tiếp

`GetConsecutiveLoss()` trả về tổng tiền lỗ của chuỗi thua gần nhất. Duyệt từ deal mới nhất về cũ nhất, cộng dồn lỗ và dừng lại khi gặp deal không thua.

```mq5
double GetConsecutiveLoss()
{
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   double totalLoss = 0.0;
   int totalDeals = HistoryDealsTotal();

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(!IsExitDealEntry(entry)) continue;

      double netProfit = GetDealNetProfit(ticket);

      if(netProfit >= 0.0)
         break;

      totalLoss += MathAbs(netProfit);
   }

   return totalLoss;
}
```

Ví dụ dùng trong flow tính lot recovery:

```mq5
double totalLoss = GetConsecutiveLoss();
if(totalLoss <= 0.0)
   return InpInitialLot;

// Tính lot cần thiết để bù đủ totalLoss theo TP đã lên kế hoạch.
```

Pattern này đơn giản, phù hợp với Martingale-style. Để kế toán chính xác trên broker tính commission vào deal ENTRY_IN, nhóm theo `DEAL_POSITION_ID` hoặc cộng thêm commission từ deal ENTRY_IN tương ứng.

## In chi tiết deal đã đóng

```mq5
void PrintClosedDealDetails(datetime fromTime, datetime toTime, ulong magicFilter, int maxRows)
{
   if(!HistorySelect(fromTime, toTime))
      return;

   int printed = 0;
   int totalDeals = HistoryDealsTotal();

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != magicFilter) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(!IsExitDealEntry(entry)) continue;

      datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double net = profit + commission + swap;

      PrintFormat("#%I64u %s %s vol=%.2f price=%.*f net=%.2f",
                  ticket,
                  TimeToString(time, TIME_DATE | TIME_MINUTES),
                  DealEntryToText(entry),
                  volume,
                  (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
                  price,
                  net);

      printed++;
      if(printed >= maxRows) break;
   }
}
```

Duyệt từ `totalDeals - 1` xuống `0` để hiển thị deal mới nhất trước.

## Win rate

```mq5
int wins = 0, losses = 0, breakeven = 0;

if(HistorySelect(fromTime, toTime))
{
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(!IsExitDealEntry(entry)) continue;

      double net = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP);

      if(net > 0.0) wins++;
      else if(net < 0.0) losses++;
      else breakeven++;
   }
}

int total = wins + losses + breakeven;
double winRate = total > 0 ? (double)wins / total * 100.0 : 0.0;
```

## Phân tích PnL theo từng ngày

Dùng khi cần báo cáo lãi/lỗ từng ngày (dashboard, log cuối phiên). Lặp từ `d = N-1` xuống `0`, tính `dayStart` và `dayEnd` cho mỗi ngày rồi gọi `CalcHistoryProfit()`.

```mq5
int nDays = 7;
datetime now = TimeCurrent();

for(int d = nDays - 1; d >= 0; d--)
{
   datetime dayStart = GetStartOfDay(now - (datetime)(d * 24 * 3600));
   datetime dayEnd   = dayStart + 86400;
   if(dayEnd > now) dayEnd = now;

   double dayProfit = CalcHistoryProfit(dayStart, dayEnd, InpMagicNumber, false);
   PrintFormat("%s : %+.2f", TimeToString(dayStart, TIME_DATE), dayProfit);
}
```

`GetStartOfDay()` cắt phần giờ/phút/giây để đảm bảo `dayStart` luôn là 00:00:00 của ngày đó. `dayEnd = dayStart + 86400` là 00:00:00 của ngày tiếp theo — không dùng `23:59:59` để tránh bỏ sót deal khớp đúng nửa đêm.

## Historical orders

Chỉ dùng historical orders khi cần metadata của order request, không phải realized PnL.

```mq5
if(HistorySelect(fromTime, toTime))
{
   int totalOrders = HistoryOrdersTotal();
   for(int i = 0; i < totalOrders; i++)
   {
      ulong orderTicket = HistoryOrderGetTicket(i);
      if(orderTicket == 0) continue;

      if((ulong)HistoryOrderGetInteger(orderTicket, ORDER_MAGIC) != InpMagicNumber) continue;
      if(HistoryOrderGetString(orderTicket, ORDER_SYMBOL) != _Symbol) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(orderTicket, ORDER_TYPE);
      ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(orderTicket, ORDER_STATE);
      double volumeInitial = HistoryOrderGetDouble(orderTicket, ORDER_VOLUME_INITIAL);
      datetime setupTime = (datetime)HistoryOrderGetInteger(orderTicket, ORDER_TIME_SETUP);
   }
}
```

Không dùng số lượng historical orders để suy ra số lệnh đã đóng. Một order có thể tạo ra nhiều deal, và netting reversal tạo ra `DEAL_ENTRY_INOUT`.
