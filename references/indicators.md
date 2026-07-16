# MQL5 Indicator Patterns

Tài liệu này gom pattern tạo indicator handle, đọc dữ liệu bằng `CopyBuffer()`, quản lý buffer, và kết hợp nhiều indicator để tạo tín hiệu giao dịch.

## Quy trình chuẩn

MQL5 không trả trực tiếp giá trị indicator từ các hàm như `iMA()` hoặc `iRSI()`. Các hàm này trả về một **handle** (`int`) đại diện cho indicator. Sau đó EA dùng handle đó để đọc dữ liệu bằng `CopyBuffer()`.

```text
OnInit()    -> tạo indicator handle và set buffer as series
OnTick()    -> CopyBuffer() để đọc giá trị indicator
OnDeinit()  -> IndicatorRelease() để giải phóng handle
```

Quy tắc quan trọng:

- Tạo handle trong `OnInit()` một lần duy nhất, không tạo trong `OnTick()`.
- Khai báo handle và buffer ở global scope nếu cần dùng trong nhiều event.
- Luôn kiểm tra `handle == INVALID_HANDLE` sau khi tạo.
- Gọi `ArraySetAsSeries(buffer, true)` một lần trong `OnInit()`.
- Luôn kiểm tra số phần tử mà `CopyBuffer()` copy được.
- Giải phóng từng handle bằng `IndicatorRelease()` trong `OnDeinit()`.
- Nếu `OnInit()` tạo nhiều handle và một handle ở giữa bị lỗi, release các handle đã tạo trước khi `return INIT_FAILED`.

## Khai báo handle và buffer

Demo dùng 6 indicator: MA, RSI, ATR, Stochastic, Bollinger Bands và MACD.

```mq5
//--- Indicator handles
int maHandle    = INVALID_HANDLE;
int rsiHandle   = INVALID_HANDLE;
int atrHandle   = INVALID_HANDLE;
int stochHandle = INVALID_HANDLE;
int bandsHandle = INVALID_HANDLE;
int macdHandle  = INVALID_HANDLE;

//--- Indicator buffers
double maBuffer[];
double rsiBuffer[];
double atrBuffer[];
double stochMainBuffer[];
double stochSignalBuffer[];
double bandsMiddleBuffer[];
double bandsUpperBuffer[];
double bandsLowerBuffer[];
double macdMainBuffer[];
double macdSignalBuffer[];
```

Luôn khởi tạo handle bằng `INVALID_HANDLE` để dễ kiểm tra trước khi release:

```mq5
int maHandle = INVALID_HANDLE;
```

## Tạo handle trong OnInit()

Tạo tất cả handle trong `OnInit()` và return `INIT_FAILED` ngay nếu indicator nào tạo lỗi. Ví dụ này dùng helper `ReleaseIndicators()` được định nghĩa ở phần release bên dưới.

```mq5
int OnInit()
{
   maHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
   {
      Print("Loi tao MA Handle! Error: ", GetLastError());
      ReleaseIndicators();
      return INIT_FAILED;
   }

   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Loi tao RSI Handle! Error: ", GetLastError());
      ReleaseIndicators();
      return INIT_FAILED;
   }

   atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Loi tao ATR Handle! Error: ", GetLastError());
      ReleaseIndicators();
      return INIT_FAILED;
   }

   stochHandle = iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   if(stochHandle == INVALID_HANDLE)
   {
      Print("Loi tao Stochastic Handle! Error: ", GetLastError());
      ReleaseIndicators();
      return INIT_FAILED;
   }

   bandsHandle = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   if(bandsHandle == INVALID_HANDLE)
   {
      Print("Loi tao Bollinger Bands Handle! Error: ", GetLastError());
      ReleaseIndicators();
      return INIT_FAILED;
   }

   macdHandle = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   if(macdHandle == INVALID_HANDLE)
   {
      Print("Loi tao MACD Handle! Error: ", GetLastError());
      ReleaseIndicators();
      return INIT_FAILED;
   }

   ArraySetAsSeries(maBuffer,          true);
   ArraySetAsSeries(rsiBuffer,         true);
   ArraySetAsSeries(atrBuffer,         true);
   ArraySetAsSeries(stochMainBuffer,   true);
   ArraySetAsSeries(stochSignalBuffer, true);
   ArraySetAsSeries(bandsMiddleBuffer, true);
   ArraySetAsSeries(bandsUpperBuffer,  true);
   ArraySetAsSeries(bandsLowerBuffer,  true);
   ArraySetAsSeries(macdMainBuffer,    true);
   ArraySetAsSeries(macdSignalBuffer,  true);

   return INIT_SUCCEEDED;
}
```

Sau khi `ArraySetAsSeries(buffer, true)`:

- `buffer[0]` là nến hiện tại.
- `buffer[1]` là nến trước.
- Dữ liệu mới nhất nằm ở index nhỏ nhất.

## CopyBuffer()

`CopyBuffer()` copy dữ liệu từ indicator handle vào array.

```mq5
int CopyBuffer(
   int    indicator_handle,
   int    buffer_num,
   int    start_pos,
   int    count,
   double buffer[]
);
```

Ý nghĩa tham số:

- `indicator_handle`: handle tạo bởi `iMA()`, `iRSI()`, `iMACD()`, ...
- `buffer_num`: số buffer của indicator.
- `start_pos`: vị trí bắt đầu, `0` là nến hiện tại.
- `count`: số giá trị cần copy.
- `buffer[]`: mảng nhận dữ liệu.

`CopyBuffer()` trả về số phần tử copy được, hoặc `-1` nếu lỗi. Nếu cần dùng `n` phần tử, kiểm tra kết quả `< n` trước khi đọc array.

```mq5
if(CopyBuffer(maHandle, 0, 0, 3, maBuffer) < 3)
   return;
```

## Buffer của các indicator phổ biến

Single-buffer indicator dùng `buffer_num = 0`:

| Hàm | Tham số chính | Buffer |
| --- | --- | --- |
| `iMA()` | symbol, timeframe, period, shift, method, price | `0` |
| `iRSI()` | symbol, timeframe, period, price | `0` |
| `iATR()` | symbol, timeframe, period | `0` |
| `iCCI()` | symbol, timeframe, period, price | `0` |
| `iMomentum()` | symbol, timeframe, period, price | `0` |
| `iDeMarker()` | symbol, timeframe, period | `0` |
| `iWPR()` | symbol, timeframe, period | `0` |
| `iForce()` | symbol, timeframe, period, method, volume | `0` |

Multi-buffer indicator:

| Hàm | Buffer |
| --- | --- |
| `iStochastic()` | `0` = Main (`MAIN_LINE`), `1` = Signal (`SIGNAL_LINE`) |
| `iBands()` | `0` = Middle/Base (`BASE_LINE`), `1` = Upper (`UPPER_BAND`), `2` = Lower (`LOWER_BAND`) |
| `iMACD()` | `0` = Main (`MAIN_LINE`), `1` = Signal (`SIGNAL_LINE`) |
| `iADX()` | `0` = Main (`MAIN_LINE`), `1` = +DI (`PLUSDI_LINE`), `2` = -DI (`MINUSDI_LINE`) |

## Enum hay dùng

`ENUM_MA_METHOD`:

| Giá trị | Ý nghĩa |
| --- | --- |
| `MODE_SMA` | Simple Moving Average |
| `MODE_EMA` | Exponential Moving Average |
| `MODE_SMMA` | Smoothed Moving Average |
| `MODE_LWMA` | Linear Weighted Moving Average |

`ENUM_APPLIED_PRICE`:

| Giá trị | Ý nghĩa |
| --- | --- |
| `PRICE_CLOSE` | Giá đóng cửa |
| `PRICE_OPEN` | Giá mở cửa |
| `PRICE_HIGH` | Giá cao nhất |
| `PRICE_LOW` | Giá thấp nhất |
| `PRICE_MEDIAN` | `(High + Low) / 2` |
| `PRICE_TYPICAL` | `(High + Low + Close) / 3` |
| `PRICE_WEIGHTED` | `(High + Low + Close + Close) / 4` |

## Đọc dữ liệu trong OnTick()

Demo chỉ xử lý khi có nến mới để tránh in log và tính toán lặp lại trên từng tick. Vì chạy ở tick đầu của nến mới, tín hiệu trade nên dùng nến đã đóng: `[1]` là nến vừa đóng, `[2]` là nến đóng trước đó.

```mq5
void OnTick()
{
   static datetime lastProcessedBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

   if(currentBar <= 0 || currentBar == lastProcessedBar)
      return;

   if(CopyBuffer(maHandle,    0, 0, 3, maBuffer)          < 3) return;
   if(CopyBuffer(rsiHandle,   0, 0, 2, rsiBuffer)         < 2) return;
   if(CopyBuffer(atrHandle,   0, 0, 2, atrBuffer)         < 2) return;
   if(CopyBuffer(stochHandle, 0, 0, 3, stochMainBuffer)   < 3) return;
   if(CopyBuffer(stochHandle, 1, 0, 3, stochSignalBuffer) < 3) return;
   if(CopyBuffer(bandsHandle, 0, 0, 2, bandsMiddleBuffer) < 2) return;
   if(CopyBuffer(bandsHandle, 1, 0, 2, bandsUpperBuffer)  < 2) return;
   if(CopyBuffer(bandsHandle, 2, 0, 2, bandsLowerBuffer)  < 2) return;
   if(CopyBuffer(macdHandle,  0, 0, 3, macdMainBuffer)    < 3) return;
   if(CopyBuffer(macdHandle,  1, 0, 3, macdSignalBuffer)  < 3) return;

   lastProcessedBar = currentBar;

   double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);

   // Dung maBuffer[1], maBuffer[2], rsiBuffer[1], ...
}
```

Số lượng copy tùy mục đích:

- Cần so sánh 2 nến đã đóng: copy ít nhất `3` phần tử và dùng `[1]`/`[2]`.
- Chỉ cần giá trị nến hiện tại để hiển thị/monitoring: copy `1` phần tử và dùng `[0]`.

## Diễn giải từng indicator

### MA

Demo dùng EMA 20:

```mq5
if(closePrice > maBuffer[1])
   Print("Gia tren MA -> xu huong tang");
else
   Print("Gia duoi MA -> xu huong giam");

if(maBuffer[1] > maBuffer[2])
   Print("MA dang doc len");
else
   Print("MA dang doc xuong");
```

### RSI

Demo dùng RSI 14:

```mq5
if(rsiBuffer[1] > 70)
   Print("RSI > 70 -> qua mua");
else if(rsiBuffer[1] < 30)
   Print("RSI < 30 -> qua ban");
else
   Print("RSI trung tinh");
```

### ATR

Demo dùng ATR 14 để gợi ý khoảng SL/TP theo volatility:

```mq5
double slPoints = atrBuffer[1] * 1.5 / _Point;
double tpPoints = atrBuffer[1] * 2.0 / _Point;
```

### Stochastic

Demo dùng Stochastic `(5, 3, 3)`:

```mq5
bool stochBuy =
   stochMainBuffer[2] < stochSignalBuffer[2] &&
   stochMainBuffer[1] > stochSignalBuffer[1];

bool stochSell =
   stochMainBuffer[2] > stochSignalBuffer[2] &&
   stochMainBuffer[1] < stochSignalBuffer[1];
```

### Bollinger Bands

Demo dùng Bollinger Bands `(20, 2.0)`:

```mq5
if(closePrice >= bandsUpperBuffer[1])
   Print("Gia tai/vuot Upper Band -> qua mua");
else if(closePrice <= bandsLowerBuffer[1])
   Print("Gia tai/duoi Lower Band -> qua ban");
else
   Print("Gia trong kenh Bollinger");
```

### MACD

Demo dùng MACD `(12, 26, 9)`:

```mq5
bool macdBuy =
   macdMainBuffer[2] < macdSignalBuffer[2] &&
   macdMainBuffer[1] > macdSignalBuffer[1];

bool macdSell =
   macdMainBuffer[2] > macdSignalBuffer[2] &&
   macdMainBuffer[1] < macdSignalBuffer[1];

if(macdMainBuffer[1] > 0)
   Print("MACD > 0 -> xu huong tang");
else
   Print("MACD < 0 -> xu huong giam");
```

## Kết hợp nhiều indicator

Demo tạo tín hiệu tổng hợp bằng RSI + Bollinger Bands + MA:

```mq5
if(rsiBuffer[1] < 30 &&
   closePrice <= bandsLowerBuffer[1] &&
   closePrice < maBuffer[1])
{
   Print("TIN HIEU MUA: RSI Oversold + Lower Band + Gia duoi MA");
}
else if(rsiBuffer[1] > 70 &&
        closePrice >= bandsUpperBuffer[1] &&
        closePrice > maBuffer[1])
{
   Print("TIN HIEU BAN: RSI Overbought + Upper Band + Gia tren MA");
}
else
{
   Print("Chua du dieu kien, tiep tuc cho");
}
```

## Hiển thị tóm tắt trên chart

Có thể dùng `Comment()` để theo dõi nhanh giá trị indicator của nến đã đóng gần nhất.

```mq5
Comment("Indicator Monitor\n",
        "Symbol: ", _Symbol, "\n",
        "MA(20):   ", DoubleToString(maBuffer[1],         _Digits), "\n",
        "RSI(14):  ", DoubleToString(rsiBuffer[1],        2),       "\n",
        "ATR(14):  ", DoubleToString(atrBuffer[1],        _Digits), "\n",
        "BB Upper: ", DoubleToString(bandsUpperBuffer[1], _Digits), "\n",
        "BB Lower: ", DoubleToString(bandsLowerBuffer[1], _Digits), "\n",
        "Close[1]: ", DoubleToString(closePrice,          _Digits));
```

## Release handles trong OnDeinit()

Mỗi handle được tạo trong `OnInit()` phải được release trong `OnDeinit()`.

```mq5
void OnDeinit(const int reason)
{
   ReleaseIndicators();
   Comment("");
}

void ReleaseIndicators()
{
   ReleaseIndicator(maHandle);
   ReleaseIndicator(rsiHandle);
   ReleaseIndicator(atrHandle);
   ReleaseIndicator(stochHandle);
   ReleaseIndicator(bandsHandle);
   ReleaseIndicator(macdHandle);
}

void ReleaseIndicator(int &handle)
{
   if(handle != INVALID_HANDLE)
   {
      IndicatorRelease(handle);
      handle = INVALID_HANDLE;
   }
}
```

Nếu chỉ release một handle, vẫn guard trước khi release:

```mq5
if(maHandle != INVALID_HANDLE)
{
   IndicatorRelease(maHandle);
   maHandle = INVALID_HANDLE;
}
```

## Indicator chaining — applied_price nhận handle của indicator khác

Hàm `iMA()` (và một số indicator khác) cho phép tham số `applied_price` nhận **handle của indicator khác** thay vì một hằng số `ENUM_APPLIED_PRICE`. Đây là cách chuẩn để tính "MA của RSI", "MA của ATR", hoặc bất kỳ MA nào áp dụng lên output của indicator khác.

```
int iMA(
   string               symbol,
   ENUM_TIMEFRAMES      period,
   int                  ma_period,
   int                  ma_shift,
   ENUM_MA_METHOD       ma_method,
   int                  applied_price   // ← có thể là ENUM_APPLIED_PRICE *hoặc* handle của indicator
);
```

Nguồn: [MQL5 docs — iMA](https://www.mql5.com/en/docs/indicators/ima)

### EMA của RSI

Tình huống phổ biến nhất: smooth RSI bằng EMA hoặc WMA để giảm nhiễu.

```mq5
//--- OnInit(): tạo RSI trước, sau đó tạo EMA dùng handle RSI làm applied_price
int g_hRsi    = INVALID_HANDLE;
int g_hEmaRsi = INVALID_HANDLE;
int g_hWmaRsi = INVALID_HANDLE;

int OnInit()
{
   g_hRsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   if(g_hRsi == INVALID_HANDLE) { Print("ERROR: RSI handle"); return INIT_FAILED; }

   // EMA(9) của RSI — dùng handle RSI làm applied_price
   g_hEmaRsi = iMA(_Symbol, PERIOD_CURRENT, 9, 0, MODE_EMA, g_hRsi);
   if(g_hEmaRsi == INVALID_HANDLE) { Print("ERROR: EMA(RSI) handle"); return INIT_FAILED; }

   // WMA(45) của RSI — cũng dùng cùng handle RSI
   g_hWmaRsi = iMA(_Symbol, PERIOD_CURRENT, 45, 0, MODE_LWMA, g_hRsi);
   if(g_hWmaRsi == INVALID_HANDLE) { Print("ERROR: WMA(RSI) handle"); return INIT_FAILED; }

   return INIT_SUCCEEDED;
}
```

```mq5
//--- OnTick(): đọc giá trị RSI, EMA(RSI), WMA(RSI) trên nến đã đóng
void OnTick()
{
   static datetime lastProcessedBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar <= 0 || curBar == lastProcessedBar) return;

   double rsiVal[2], emaVal[2], wmaVal[2];
   if(CopyBuffer(g_hRsi,    0, 1, 2, rsiVal) < 2) return;
   if(CopyBuffer(g_hEmaRsi, 0, 1, 2, emaVal) < 2) return;
   if(CopyBuffer(g_hWmaRsi, 0, 1, 2, wmaVal) < 2) return;

   lastProcessedBar = curBar;

   double rsiCurrent = rsiVal[1];  // bar[1] = nến vừa đóng
   double emaCurrent = emaVal[1];
   double wmaCurrent = wmaVal[1];
   double rsiPrev    = rsiVal[0];  // bar[2]
   double emaPrev    = emaVal[0];
   double wmaPrev    = wmaVal[0];

   // Ví dụ: tín hiệu RSI cắt lên EMA9 và EMA9 đang trên WMA45
   bool crossUp = (rsiPrev < emaPrev) && (rsiCurrent > emaCurrent) && (emaCurrent > wmaCurrent);
   bool crossDn = (rsiPrev > emaPrev) && (rsiCurrent < emaCurrent) && (emaCurrent < wmaCurrent);
}
```

```mq5
//--- OnDeinit(): release theo thứ tự ngược — child handle trước, parent sau
void OnDeinit(const int reason)
{
   if(g_hWmaRsi != INVALID_HANDLE) { IndicatorRelease(g_hWmaRsi); g_hWmaRsi = INVALID_HANDLE; }
   if(g_hEmaRsi != INVALID_HANDLE) { IndicatorRelease(g_hEmaRsi); g_hEmaRsi = INVALID_HANDLE; }
   if(g_hRsi    != INVALID_HANDLE) { IndicatorRelease(g_hRsi);    g_hRsi    = INVALID_HANDLE; }
}
```

### Quy tắc quan trọng khi chaining

- **Tạo parent handle trước**: `iRSI()` phải được tạo trước khi truyền handle của nó vào `iMA()`.
- **Release theo thứ tự ngược**: release child (EMA/WMA) trước, release parent (RSI) sau — tránh dangling reference.
- **Cùng symbol và timeframe**: parent và child indicator phải dùng cùng `symbol` và `timeframe`.
- **Mỗi timeframe cần bộ handle riêng**: nếu cần EMA(RSI) trên cả M15 và H1, tạo 2 bộ handle độc lập.
- **CopyBuffer() đọc trực tiếp từ child handle**: không cần đọc RSI rồi tính EMA thủ công — `CopyBuffer(g_hEmaRsi, ...)` trả kết quả đã smooth.

### Indicator khác hỗ trợ handle làm applied_price

`iMA()` là phổ biến nhất, nhưng nhiều indicator cũng cho phép:

| Hàm | Tham số nhận handle |
|-----|----------------------|
| `iMA()` | `applied_price` |
| `iRSI()` | `applied_price` |
| `iCCI()` | `applied_price` |
| `iMomentum()` | `applied_price` |
| `iStdDev()` | `applied_price` |

Ví dụ RSI của MA: tạo MA trước, truyền handle MA vào `iRSI()` làm `applied_price`.

## Sai lầm thường gặp

Tạo handle trong `OnTick()`:

```mq5
void OnTick()
{
   int handle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE); // Sai
}
```

Lỗi này tạo handle mới ở mỗi tick và dễ gây rò rỉ tài nguyên. Hãy tạo handle một lần trong `OnInit()`.

Gọi `ArraySetAsSeries()` trong `OnTick()`:

```mq5
void OnTick()
{
   ArraySetAsSeries(maBuffer, true); // Khong can lap lai moi tick
}
```

Lỗi này làm giảm hiệu năng của EA khi gọi hàm thiết lập thuộc tính mảng liên tục mỗi tick. Hãy khai báo các mảng buffer nhận dữ liệu dưới dạng biến toàn cục (global variables) và gọi `ArraySetAsSeries()` một lần duy nhất cho các mảng này trong `OnInit()`. Chỉ khai báo cục bộ và gọi trong `OnTick()` khi thực sự bắt buộc.

Không kiểm tra `CopyBuffer()`:

```mq5
CopyBuffer(maHandle, 0, 0, 2, maBuffer);
double ma = maBuffer[0]; // Co the sai neu data chua san sang
```

Hãy kiểm tra đúng số phần tử cần dùng:

```mq5
if(CopyBuffer(maHandle, 0, 0, 2, maBuffer) < 2)
   return;
```

Quên release handle:

```mq5
void OnDeinit(const int reason)
{
   // Sai: khong release handle
}
```

Hãy release đầy đủ tất cả handle đã tạo.

## Kiểm tra crossover

### Nguyên tắc chọn index

```
Khi dùng ArraySetAsSeries(true):

  [0] = nến đang hình thành (chưa đóng) — giá trị thay đổi mỗi tick
  [1] = nến vừa đóng        (hoàn thành) — giá trị cố định
  [2] = nến trước đó        (hoàn thành) — giá trị cố định
```

| Mục đích | So sánh index | Cần CopyBuffer count |
|---|---|---|
| Crossover ngay lập tức (real-time, chưa cần đóng nến) | [0] vs [1] | 2 |
| Crossover đã xác nhận (nến vừa đóng hoàn thành) | [1] vs [2] | 3 |

**Dùng [1] vs [2] an toàn hơn** — tránh tín hiệu giả do nến chưa đóng.

### Loại 1: Hai indicator cắt nhau (ví dụ %K cắt %D, MACD cắt Signal)

```mq5
// Ví dụ: Stochastic %K cắt lên %D trên nến ĐÃ ĐÓNG
double kBuf[], dBuf[];
ArraySetAsSeries(kBuf, true);
ArraySetAsSeries(dBuf, true);
if(CopyBuffer(hStoch, 0, 0, 3, kBuf) < 3) return;
if(CopyBuffer(hStoch, 1, 0, 3, dBuf) < 3) return;

// [1] = nến vừa đóng, [2] = nến trước — cả hai đã hoàn thành
bool kCrossAboveD = (kBuf[2] < dBuf[2]) && (kBuf[1] > dBuf[1]);
bool kCrossBelowD = (kBuf[2] > dBuf[2]) && (kBuf[1] < dBuf[1]);

// Nếu muốn real-time (dùng [0] vs [1], chỉ cần count=2)
// bool kCrossAboveD_rt = (kBuf[1] < dBuf[1]) && (kBuf[0] > dBuf[0]);
```

### Loại 2: Indicator cắt một ngưỡng cố định (ví dụ RSI cắt 30/70)

```mq5
double rsi[];
ArraySetAsSeries(rsi, true);
if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return;

double level = 30.0;  // ngưỡng cần kiểm tra

// Cắt LÊN ngưỡng (vd: RSI vượt lên 30 — thoát vùng oversold)
// Nến đã đóng: dùng [1] và [2]
bool crossAboveLevel = (rsi[2] < level) && (rsi[1] > level);

// Cắt XUỐNG ngưỡng (vd: RSI rơi xuống 70 — thoát vùng overbought)
bool crossBelowLevel = (rsi[2] > level) && (rsi[1] < level);

// Real-time (dùng [0] và [1], không cần đợi nến đóng)
// bool crossAboveLevel_rt = (rsi[1] < level) && (rsi[0] > level);
// bool crossBelowLevel_rt = (rsi[1] > level) && (rsi[0] < level);
```

## iCustom — Dùng custom indicator

`iCustom()` là hàm tạo handle cho bất kỳ custom indicator nào (`.ex5`) nằm trong thư mục `MQL5/Indicators/` hoặc subfolder của nó. Trả về `int` handle — giống hệt `iMA()`, `iRSI()` — dùng với `CopyBuffer()` để đọc dữ liệu.

### Signature

```mq5
int iCustom(
   string          symbol,    // symbol, NULL = chart hiện tại
   ENUM_TIMEFRAMES period,    // timeframe, 0 = chart hiện tại
   string          name,      // tên file indicator (không có .ex5)
   ...                        // tham số của indicator (theo thứ tự input)
);
```

### Tham số `name` — đường dẫn indicator

Tên file tính từ gốc `MQL5/Indicators/`. Không cần đuôi `.ex5`.

```mq5
// Indicator nằm tại MQL5/Indicators/supertrend.ex5
iCustom(_Symbol, _Period, "supertrend", ...)

// Indicator nằm tại MQL5/Indicators/MyFolder/MyInd.ex5
iCustom(_Symbol, _Period, "MyFolder\\MyInd", ...)
```

### Truyền tham số cho indicator

Các tham số sau `name` được map theo thứ tự khai báo `input` trong file indicator. **Kiểu dữ liệu phải khớp chính xác** — sai kiểu sẽ gây `INVALID_HANDLE` hoặc logic sai lặng lẽ.

```
// Trong indicator:
input int    AtrPeriod     = 10;   // tham số 1 — kiểu int
input double AtrMultiplier = 3.0;  // tham số 2 — kiểu double
input bool   ShowLabels    = true; // tham số 3 — kiểu bool

// Trong EA:
iCustom(_Symbol, _Period, "supertrend",
        20,      // int    — AtrPeriod
        3.5,     // double — AtrMultiplier
        false);  // bool   — ShowLabels
```

Nếu indicator có tham số kiểu `ENUM_*`, truyền giá trị enum tương ứng hoặc cast về `int`:

```mq5
// input ENUM_MA_METHOD MaMethod = MODE_EMA; trong indicator
iCustom(_Symbol, _Period, "my_indicator", 14, (int)MODE_EMA, PRICE_CLOSE);
```

### Buffer numbering

Buffer số trong `CopyBuffer()` tương ứng với thứ tự gọi `SetIndexBuffer()` trong indicator, bắt đầu từ `0`.

```
// Trong indicator (ví dụ Supertrend):
SetIndexBuffer(0, UpTrendBuffer,   INDICATOR_DATA);  // buffer 0
SetIndexBuffer(1, DownTrendBuffer, INDICATOR_DATA);  // buffer 1

// Trong EA:
CopyBuffer(handle, 0, 0, 3, upBuf);   // đọc UpTrendBuffer
CopyBuffer(handle, 1, 0, 3, dnBuf);   // đọc DownTrendBuffer
```

Nếu không có source code indicator, mở indicator trên chart và đếm số đường vẽ — thứ tự từ trên xuống trong Properties thường tương ứng với thứ tự buffer. Nếu vẫn không chắc, dùng thử từng buffer number.

### EMPTY_VALUE — phát hiện vùng không có giá trị

Nhiều indicator (Supertrend, Zigzag, ...) chỉ vẽ một phần buffer — các bar còn lại được set bằng `EMPTY_VALUE` (= `DBL_MAX`). Dùng hằng số `EMPTY_VALUE` để kiểm tra trực tiếp.

```mq5
// Phát hiện buffer có giá trị tại nến vừa đóng
if(upBuf[1] != EMPTY_VALUE)
   Print("UpTrend active at bar[1]");

// Phát hiện chuyển trạng thái: buffer bắt đầu có giá trị tại [1]
bool trendStarted = (upBuf[1] != EMPTY_VALUE) && (upBuf[2] == EMPTY_VALUE);
```

**Lưu ý:** So sánh `== EMPTY_VALUE` chính xác vì `EMPTY_VALUE` là sentinel cố định (`DBL_MAX`), không phải số tính toán — không cần dùng `MathAbs` hay epsilon.

### Ví dụ đầy đủ — Supertrend với 2 buffer

Supertrend có 2 buffer: `UpTrend` (buffer 0) và `DownTrend` (buffer 1). Mỗi bar chỉ một trong hai buffer có giá trị; buffer còn lại là `EMPTY_VALUE`.

```mq5
//--- Global
int    g_stHandle = INVALID_HANDLE;
double g_upBuf[];
double g_dnBuf[];

//--- OnInit()
g_stHandle = iCustom(_Symbol, _Period, "supertrend",
                     20,    // ATR Period  (int)
                     3.5);  // ATR Multiplier (double)
if(g_stHandle == INVALID_HANDLE)
{
   Print("Supertrend handle failed. Error: ", GetLastError());
   return INIT_FAILED;
}
ArraySetAsSeries(g_upBuf, true);
ArraySetAsSeries(g_dnBuf, true);

//--- OnTick() — chỉ chạy khi có nến mới
if(CopyBuffer(g_stHandle, 0, 0, 3, g_upBuf) < 3) return;
if(CopyBuffer(g_stHandle, 1, 0, 3, g_dnBuf) < 3) return;

// Tín hiệu chuyển từ DownTrend sang UpTrend
bool buySignal  = (g_upBuf[1] != EMPTY_VALUE) && (g_upBuf[2] == EMPTY_VALUE);
// Tín hiệu chuyển từ UpTrend sang DownTrend
bool sellSignal = (g_dnBuf[1] != EMPTY_VALUE) && (g_dnBuf[2] == EMPTY_VALUE);

//--- OnDeinit()
if(g_stHandle != INVALID_HANDLE)
{
   IndicatorRelease(g_stHandle);
   g_stHandle = INVALID_HANDLE;
}
```

### Pitfalls thường gặp với iCustom

| Triệu chứng | Nguyên nhân |
|---|---|
| `INVALID_HANDLE` ngay lập tức | File `.ex5` không tồn tại hoặc đường dẫn sai; indicator chưa được compile |
| Handle hợp lệ nhưng `CopyBuffer` trả `-1` | Indicator đang load dữ liệu lần đầu — thử lại tick sau |
| Giá trị buffer sai hoặc tất cả bằng 0 | Sai thứ tự hoặc kiểu tham số truyền vào |
| Buffer toàn `EMPTY_VALUE` | Sai buffer number; hoặc indicator không vẽ gì trên symbol/timeframe đó |
| EA compile được nhưng indicator chạy sai logic | Tham số `int` bị truyền `double` ngầm (ví dụ truyền `3.0` cho tham số `int`) |
