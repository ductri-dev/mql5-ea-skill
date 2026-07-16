# MQL5 Arrays & Time Series

## Khái niệm time series

Mảng thường trong MQL5 dùng index tăng theo thứ tự tự nhiên: index nhỏ trước, index lớn sau. Khi copy dữ liệu time series vào mảng thường, phần tử cũ nhất nằm ở index nhỏ nhất.

Sau khi `ArraySetAsSeries(arr, true)`:
- `arr[0]` = bar hiện tại (đang hình thành)
- `arr[1]` = bar đã đóng gần nhất
- `arr[2]` = bar đã đóng trước nữa

Nếu code muốn đọc theo kiểu trading (`[0]` = bar hiện tại), hãy dùng `ArraySetAsSeries(arr, true)` cho mảng nhận dữ liệu từ `CopyBuffer()` / `CopyXxx()` / `CopyRates()`.

`ArraySetAsSeries()` chỉ đổi hướng index khi truy cập; nó không đảo thứ tự lưu vật lý trong bộ nhớ.

Lưu ý cho EA trade theo nến đóng:
- `[0]` là bar đang hình thành, có thể đổi liên tục trong nến.
- `[1]` là bar đã đóng gần nhất.
- Nếu dùng logic nến mới rồi kiểm tín hiệu crossover, thường so `[2] -> [1]`, không so `[1] -> [0]`.

---

## CopyClose, CopyOpen, CopyHigh, CopyLow

```mq5
double close[];
ArraySetAsSeries(close, true);

// Copy 10 giá trị: từ bar 0 (hiện tại) đến bar 9
int copied = CopyClose(_Symbol, _Period, 0, 10, close);
if(copied < 10)
{
   Print("CopyClose failed: ", GetLastError());
   return;
}

double closeNow  = close[0];   // bar hiện tại
double closePrev = close[1];   // bar đã đóng gần nhất
```

**Signature:** `CopyClose(symbol, timeframe, start_pos, count, array[])`

---

## CopyRates — lấy OHLCV cùng lúc

```mq5
MqlRates rates[];
ArraySetAsSeries(rates, true);

if(CopyRates(_Symbol, _Period, 0, 10, rates) < 10) return;

datetime time  = rates[0].time;
double   open  = rates[0].open;
double   high  = rates[0].high;
double   low   = rates[0].low;
double   close = rates[0].close;
long     vol   = rates[0].tick_volume;
```

---

## CopyTime, CopyTickVolume

```mq5
// Lấy time của các bars
datetime times[];
ArraySetAsSeries(times, true);
if(CopyTime(_Symbol, _Period, 0, 5, times) < 5) return;

// Lấy tick volume của các bars
long tickVolumes[];
ArraySetAsSeries(tickVolumes, true);
if(CopyTickVolume(_Symbol, _Period, 0, 5, tickVolumes) < 5) return;

datetime currentBarTime = times[0];
long     currentVolume  = tickVolumes[0];
```

---

## iTime, iClose, iOpen, iHigh, iLow — truy cập theo index

```mq5
// Truy cập giá trị đơn lẻ theo bar index (không cần array)
datetime barTime  = iTime(_Symbol, _Period, 0);   // 0 = hiện tại
double   prevClose= iClose(_Symbol, _Period, 1);  // 1 = bar đã đóng
double   prevHigh = iHigh(_Symbol, _Period, 1);
double   prevLow  = iLow(_Symbol, _Period, 1);
int      barCount = iBars(_Symbol, _Period);
```

**Dùng `iXxx()` khi chỉ cần 1 giá trị. Dùng `CopyXxx()` khi cần nhiều giá trị liên tiếp.**

---

## Multi-timeframe arrays

```mq5
// Lấy close của H4 từ chart M15
double h4Close[];
ArraySetAsSeries(h4Close, true);
if(CopyClose(_Symbol, PERIOD_H4, 0, 5, h4Close) < 5) return;

// Lấy OHLC của D1
MqlRates d1Rates[];
ArraySetAsSeries(d1Rates, true);
if(CopyRates(_Symbol, PERIOD_D1, 0, 10, d1Rates) < 10) return;
```

---

## ArraySetAsSeries — các trường hợp dễ quên

```mq5
// CopyBuffer buffer — cần SetAsSeries nếu code giả định [0]=bar hiện tại
double maBuffer[];
ArraySetAsSeries(maBuffer, true);
if(CopyBuffer(g_maHandle, 0, 0, 3, maBuffer) < 3) return;

// Dynamic array thông thường — không cần SetAsSeries
double myArr[];
ArrayResize(myArr, 100);
// myArr[0] là phần tử đầu tiên bạn gán vào
```

`ArraySetAsSeries()` không dùng được với static array (`double a[10]`) hoặc multi-dimensional array.

---

## Lỗi phổ biến với arrays

```mq5
// ❌ SAI: quên kiểm tra return value của CopyBuffer
double uncheckedBuf[];
ArraySetAsSeries(uncheckedBuf, true);
CopyBuffer(handle, 0, 0, 3, uncheckedBuf);
double uncheckedVal = uncheckedBuf[0];   // buffer có thể rỗng nếu copy thất bại

// ✅ ĐÚNG: luôn kiểm tra
double checkedBuf[];
ArraySetAsSeries(checkedBuf, true);
if(CopyBuffer(handle, 0, 0, 3, checkedBuf) < 3) return;
double checkedVal = checkedBuf[0];

// ❌ SAI: dùng array chưa SetAsSeries
double rawClose[];
if(CopyClose(_Symbol, _Period, 0, 3, rawClose) < 3) return;
double rawCurrent = rawClose[0];   // rawClose[0] là bar CŨ NHẤT, không phải hiện tại!

// ✅ ĐÚNG:
double seriesClose[];
ArraySetAsSeries(seriesClose, true);
if(CopyClose(_Symbol, _Period, 0, 3, seriesClose) < 3) return;
double current = seriesClose[0];   // seriesClose[0] = bar hiện tại
```

---

## Tìm High/Low trong một range

```mq5
// High nhất trong 20 bar gần nhất
double high[];
double low[];
ArraySetAsSeries(high, true);
ArraySetAsSeries(low, true);
if(CopyHigh(_Symbol, _Period, 0, 20, high) < 20) return;
if(CopyLow(_Symbol, _Period, 0, 20, low) < 20) return;

double highest = high[ArrayMaximum(high, 0, 20)];
double lowest  = low[ArrayMinimum(low, 0, 20)];

// Dùng iHighest / iLowest (trả index của bar)
int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, 20, 0);
if(highestIdx < 0) return;
double highestVal = iHigh(_Symbol, _Period, highestIdx);
```
