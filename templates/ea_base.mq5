//+------------------------------------------------------------------+
//|  EA Base Template — MQL5                                         |
//|  Xóa comment và input không cần, giữ cấu trúc                    |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Trading ===";
input double InpLotSize      = 0.1;
input long   InpMagicNumber  = 12345;
input int    InpMarketOpenMaxTickAgeSec = 60; // 0 = disable tick freshness check

input group "=== Indicator ===";
input int    InpMaPeriod     = 20;
input ENUM_MA_METHOD         InpMaMethod  = MODE_EMA;
input ENUM_APPLIED_PRICE     InpMaPrice   = PRICE_CLOSE;

//--- Global variables
CTrade trade;
int    g_maHandle = INVALID_HANDLE;
datetime g_lastProcessedBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_maHandle = iMA(_Symbol, _Period, InpMaPeriod, 0, InpMaMethod, InpMaPrice);
   if(g_maHandle == INVALID_HANDLE)
   {
      Print("Failed to create MA handle, error: ", GetLastError());
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_maHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_maHandle);
      g_maHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(!IsNewBarCandidate(currentBarTime)) return;

   if(!IsTradeAllowed())
   {
      MarkBarProcessed(currentBarTime);
      return;
   }

   if(!IsMarketOpen())
   {
      MarkBarProcessed(currentBarTime);
      return;
   }

   //--- Read indicator
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_maHandle, 0, 0, 3, ma) < 3) return;

   //--- Read price
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, _Period, 0, 3, close) < 3) return;

   //--- Data is ready. Mark before trading to avoid duplicate execution on the same bar.
   MarkBarProcessed(currentBarTime);

   //--- Signals based on closed bars: [1] is latest closed bar, [2] is previous closed bar.
   bool buySignal  = (close[2] < ma[2]) && (close[1] > ma[1]);
   bool sellSignal = (close[2] > ma[2]) && (close[1] < ma[1]);

   //--- Execute
   bool hasPosition = HasPosition();
   if(buySignal && !hasPosition)
      OpenBuy();
   else if(sellSignal && !hasPosition)
      OpenSell();
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   if(!IsTradeAllowed() || !IsMarketOpen()) return;

   double lot = NormalizeVolume(InpLotSize);
   if(lot <= 0.0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0) return;

   double ask    = tick.ask;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) return;

   double sl     = NormalizeDouble(ask - 100 * point, _Digits);
   double tp     = NormalizeDouble(ask + 200 * point, _Digits);

   if(!ValidateStops(ORDER_TYPE_BUY, ask, sl, tp)) return;

   CheckTradeResult("Buy", trade.Buy(lot, _Symbol, ask, sl, tp, "MA cross buy"));
}

//+------------------------------------------------------------------+
void OpenSell()
{
   if(!IsTradeAllowed() || !IsMarketOpen()) return;

   double lot = NormalizeVolume(InpLotSize);
   if(lot <= 0.0) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0) return;

   double bid   = tick.bid;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) return;

   double sl    = NormalizeDouble(bid + 100 * point, _Digits);
   double tp    = NormalizeDouble(bid - 200 * point, _Digits);

   if(!ValidateStops(ORDER_TYPE_SELL, bid, sl, tp)) return;

   CheckTradeResult("Sell", trade.Sell(lot, _Symbol, bid, sl, tp, "MA cross sell"));
}

//+------------------------------------------------------------------+
int GetVolumeDigitsByStep(double lotStep)
{
   int digits = 0;
   double step = lotStep;

   while(digits < 8 && MathAbs(step - MathRound(step)) > 0.000000001)
   {
      step *= 10.0;
      digits++;
   }

   return digits;
}

//+------------------------------------------------------------------+
double NormalizeVolume(double volume)
{
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotMin <= 0.0 || lotMax <= 0.0 || lotStep <= 0.0 || lotMax < lotMin)
   {
      PrintFormat("Invalid volume settings: min=%.8f max=%.8f step=%.8f",
                  lotMin, lotMax, lotStep);
      return 0.0;
   }

   volume = MathMax(lotMin, MathMin(lotMax, volume));

   double steps = MathFloor(((volume - lotMin) / lotStep) + 0.000000001);
   double normalized = lotMin + steps * lotStep;
   normalized = MathMax(lotMin, MathMin(lotMax, normalized));

   return NormalizeDouble(normalized, GetVolumeDigitsByStep(lotStep));
}

//+------------------------------------------------------------------+
bool ValidateStops(const ENUM_ORDER_TYPE orderType,
                   const double entryPrice,
                   const double sl,
                   const double tp)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   if(point <= 0.0)
      return false;

   if(stopsLevel <= 0)
      return true;

   double minDistance = stopsLevel * point;

   if(orderType == ORDER_TYPE_BUY)
   {
      if(sl > 0.0 && entryPrice - sl < minDistance)
      {
         PrintFormat("Buy SL too close: distance=%.1f points, required=%d",
                     (entryPrice - sl) / point, stopsLevel);
         return false;
      }
      if(tp > 0.0 && tp - entryPrice < minDistance)
      {
         PrintFormat("Buy TP too close: distance=%.1f points, required=%d",
                     (tp - entryPrice) / point, stopsLevel);
         return false;
      }
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      if(sl > 0.0 && sl - entryPrice < minDistance)
      {
         PrintFormat("Sell SL too close: distance=%.1f points, required=%d",
                     (sl - entryPrice) / point, stopsLevel);
         return false;
      }
      if(tp > 0.0 && entryPrice - tp < minDistance)
      {
         PrintFormat("Sell TP too close: distance=%.1f points, required=%d",
                     (entryPrice - tp) / point, stopsLevel);
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
bool IsTradeRetcodeSuccess(const uint retcode)
{
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL ||
          retcode == TRADE_RETCODE_PLACED;
}

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool IsNewBarCandidate(const datetime currentBarTime)
{
   return currentBarTime > 0 && currentBarTime != g_lastProcessedBarTime;
}

//+------------------------------------------------------------------+
void MarkBarProcessed(const datetime barTime)
{
   if(barTime > 0)
      g_lastProcessedBarTime = barTime;
}

//+------------------------------------------------------------------+
// Kiểm tra EA được phép trade (nút Algo Trading trên terminal).
// Không phải built-in — PHẢI định nghĩa trong mọi file EA.
bool IsTradeAllowed()
{
   return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
          (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}

//+------------------------------------------------------------------+
datetime LastTickTime()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return 0;
   return tick.time;
}

//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE)
      != SYMBOL_TRADE_MODE_FULL) return false;

   if(InpMarketOpenMaxTickAgeSec <= 0)
      return true;

   datetime tickTime = LastTickTime();
   if(tickTime == 0) return false;

   return (TimeTradeServer() - tickTime) <= InpMarketOpenMaxTickAgeSec;
}
