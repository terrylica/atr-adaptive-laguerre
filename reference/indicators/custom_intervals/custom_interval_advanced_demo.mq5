//+------------------------------------------------------------------+
//| Advanced Custom Interval Demo                                    |
//| Uses CopyRates for efficient custom interval creation           |
//+------------------------------------------------------------------+
#property copyright "Demo - Advanced Custom Interval"
#property link      ""
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   1
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrRed
#property indicator_width1  2

//--- Input parameters
input int    InpCustomInterval = 15;         // Custom interval in minutes (0 = use chart timeframe)
input string InpCustomSymbol = "";           // Custom symbol (empty = current symbol)
input ENUM_TIMEFRAMES InpBaseTimeframe = PERIOD_M1; // Base timeframe for custom interval
input int    InpSMAPeriod = 14;              // SMA Period for demonstration
input bool   InpShowDebug = true;            // Show debug information

//--- Global variables
double ValueBuffer[];
double ColorBuffer[];
MqlRates CustomBars[];
string WorkSymbol;
datetime LastProcessedTime = 0;

//--- Structures for custom interval management
struct CustomIntervalData
{
   datetime startTime;
   double   open;
   double   high; 
   double   low;
   double   close;
   long     volume;
   bool     isComplete;
};

CustomIntervalData CurrentInterval;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Setup indicator buffers
   SetIndexBuffer(0, ValueBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
   
   //--- Determine working symbol
   WorkSymbol = (InpCustomSymbol == "") ? _Symbol : InpCustomSymbol;
   
   //--- Set indicator properties
   string intervalStr = (InpCustomInterval == 0) ? "Chart TF" : IntegerToString(InpCustomInterval) + "min";
   string shortName = StringFormat("CustomSMA(%s, %s, %d)", WorkSymbol, intervalStr, InpSMAPeriod);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   
   //--- Initialize custom interval
   ResetCurrentInterval();
   
   if(InpShowDebug)
   {
      Print("=== Custom Interval Indicator Initialized ===");
      Print("Symbol: ", WorkSymbol);
      Print("Custom Interval: ", InpCustomInterval, " minutes");
      Print("Base Timeframe: ", EnumToString(InpBaseTimeframe));
      Print("SMA Period: ", InpSMAPeriod);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Reset current interval data                                      |
//+------------------------------------------------------------------+
void ResetCurrentInterval()
{
   CurrentInterval.startTime = 0;
   CurrentInterval.open = 0;
   CurrentInterval.high = 0;
   CurrentInterval.low = 0;
   CurrentInterval.close = 0;
   CurrentInterval.volume = 0;
   CurrentInterval.isComplete = false;
}

//+------------------------------------------------------------------+
//| Custom indicator calculation function                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- If custom interval is 0, use chart timeframe directly
   if(InpCustomInterval == 0)
   {
      return CalculateOnChartTimeframe(rates_total, prev_calculated, close);
   }
   
   //--- Otherwise, build custom intervals
   return CalculateOnCustomInterval(rates_total, prev_calculated);
}

//+------------------------------------------------------------------+
//| Calculate using chart timeframe directly                         |
//+------------------------------------------------------------------+
int CalculateOnChartTimeframe(int rates_total, int prev_calculated, const double &close[])
{
   int limit = (prev_calculated > InpSMAPeriod) ? prev_calculated - 1 : InpSMAPeriod - 1;
   
   for(int i = limit; i < rates_total; i++)
   {
      if(i < InpSMAPeriod - 1)
      {
         ValueBuffer[i] = 0;
         ColorBuffer[i] = 0;
         continue;
      }
      
      //--- Calculate Simple Moving Average
      double sum = 0;
      for(int j = 0; j < InpSMAPeriod; j++)
      {
         sum += close[i - j];
      }
      
      ValueBuffer[i] = sum / InpSMAPeriod;
      
      //--- Set color based on trend
      if(i > 0)
         ColorBuffer[i] = (ValueBuffer[i] > ValueBuffer[i-1]) ? 0 : 1;
      else
         ColorBuffer[i] = 0;
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Calculate using custom interval                                  |
//+------------------------------------------------------------------+
int CalculateOnCustomInterval(int rates_total, int prev_calculated)
{
   //--- Get base timeframe data
   MqlRates baseRates[];
   int baseBarCount = CopyRates(WorkSymbol, InpBaseTimeframe, 0, rates_total * 2, baseRates);
   
   if(baseBarCount <= 0)
   {
      if(InpShowDebug)
         Print("Failed to copy rates for ", WorkSymbol, ", Error: ", GetLastError());
      return prev_calculated;
   }
   
   //--- Build custom intervals from base data
   BuildCustomIntervals(baseRates, baseBarCount);
   
   //--- Calculate indicator on custom intervals
   CalculateIndicatorOnCustomBars();
   
   //--- Map results to chart
   MapCustomBarsToChart(rates_total);
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Build custom intervals from base timeframe data                  |
//+------------------------------------------------------------------+
void BuildCustomIntervals(const MqlRates &baseRates[], int count)
{
   //--- Clear existing custom bars
   ArrayResize(CustomBars, 0);
   ResetCurrentInterval();
   
   for(int i = 0; i < count; i++)
   {
      datetime barTime = baseRates[i].time;
      datetime intervalStart = GetCustomIntervalStart(barTime);
      
      //--- Check if we need to start a new interval
      if(intervalStart != CurrentInterval.startTime)
      {
         //--- Save completed interval
         if(CurrentInterval.startTime > 0)
         {
            SaveCurrentInterval();
         }
         
         //--- Start new interval
         StartNewInterval(intervalStart, baseRates[i]);
      }
      
      //--- Update current interval
      UpdateCurrentInterval(baseRates[i]);
   }
   
   //--- Save the last interval
   if(CurrentInterval.startTime > 0)
   {
      SaveCurrentInterval();
   }
   
   if(InpShowDebug && ArraySize(CustomBars) > 0)
   {
      int customBarCount = ArraySize(CustomBars);
      Print(StringFormat("Built %d custom %d-minute bars from %d base bars", 
            customBarCount, InpCustomInterval, count));
      
      //--- Show last few custom bars
      int showCount = MathMin(3, customBarCount);
      for(int i = customBarCount - showCount; i < customBarCount; i++)
      {
         Print(StringFormat("Custom Bar[%d]: %s O:%.5f H:%.5f L:%.5f C:%.5f V:%d",
               i, TimeToString(CustomBars[i].time), 
               CustomBars[i].open, CustomBars[i].high, 
               CustomBars[i].low, CustomBars[i].close, 
               CustomBars[i].tick_volume));
      }
   }
}

//+------------------------------------------------------------------+
//| Get custom interval start time                                   |
//+------------------------------------------------------------------+
datetime GetCustomIntervalStart(datetime barTime)
{
   //--- Convert to minutes since start of week (Monday 00:00)
   int dayOfWeek = (int)TimeDayOfWeek(barTime);
   if(dayOfWeek == 0) dayOfWeek = 7; // Sunday = 7
   
   //--- Get start of week
   datetime weekStart = barTime - ((dayOfWeek - 1) * 24 * 3600) - (barTime % (24 * 3600));
   
   //--- Calculate total minutes since week start
   int totalMinutes = (int)((barTime - weekStart) / 60);
   
   //--- Calculate interval number and start
   int intervalNumber = totalMinutes / InpCustomInterval;
   int intervalStartMinutes = intervalNumber * InpCustomInterval;
   
   return weekStart + intervalStartMinutes * 60;
}

//+------------------------------------------------------------------+
//| Start new custom interval                                        |
//+------------------------------------------------------------------+
void StartNewInterval(datetime startTime, const MqlRates &firstBar)
{
   CurrentInterval.startTime = startTime;
   CurrentInterval.open = firstBar.open;
   CurrentInterval.high = firstBar.high;
   CurrentInterval.low = firstBar.low;
   CurrentInterval.close = firstBar.close;
   CurrentInterval.volume = firstBar.tick_volume;
   CurrentInterval.isComplete = false;
}

//+------------------------------------------------------------------+
//| Update current interval with new bar data                        |
//+------------------------------------------------------------------+
void UpdateCurrentInterval(const MqlRates &bar)
{
   //--- Update high/low
   if(bar.high > CurrentInterval.high)
      CurrentInterval.high = bar.high;
   if(bar.low < CurrentInterval.low)
      CurrentInterval.low = bar.low;
   
   //--- Update close and volume
   CurrentInterval.close = bar.close;
   CurrentInterval.volume += bar.tick_volume;
}

//+------------------------------------------------------------------+
//| Save completed interval to custom bars array                     |
//+------------------------------------------------------------------+
void SaveCurrentInterval()
{
   int size = ArraySize(CustomBars);
   ArrayResize(CustomBars, size + 1);
   
   CustomBars[size].time = CurrentInterval.startTime;
   CustomBars[size].open = CurrentInterval.open;
   CustomBars[size].high = CurrentInterval.high;
   CustomBars[size].low = CurrentInterval.low;
   CustomBars[size].close = CurrentInterval.close;
   CustomBars[size].tick_volume = CurrentInterval.volume;
   CustomBars[size].spread = 0;
   CustomBars[size].real_volume = 0;
   
   CurrentInterval.isComplete = true;
}

//+------------------------------------------------------------------+
//| Calculate indicator values on custom bars                        |
//+------------------------------------------------------------------+
void CalculateIndicatorOnCustomBars()
{
   int customBarCount = ArraySize(CustomBars);
   
   if(customBarCount < InpSMAPeriod)
      return;
   
   //--- Calculate SMA on custom bars
   for(int i = InpSMAPeriod - 1; i < customBarCount; i++)
   {
      double sum = 0;
      for(int j = 0; j < InpSMAPeriod; j++)
      {
         sum += CustomBars[i - j].close;
      }
      
      double smaValue = sum / InpSMAPeriod;
      
      //--- Store calculated value (we'll map it to chart later)
      //--- For now, we can add it as a custom field or use a separate array
   }
}

//+------------------------------------------------------------------+
//| Map custom bar results to chart display                          |
//+------------------------------------------------------------------+
void MapCustomBarsToChart(int rates_total)
{
   //--- Get current chart time data
   datetime chartTimes[];
   if(CopyTime(_Symbol, _Period, 0, rates_total, chartTimes) != rates_total)
      return;
   
   int customBarCount = ArraySize(CustomBars);
   if(customBarCount < InpSMAPeriod)
      return;
   
   //--- Map custom bar values to chart bars
   for(int chartIdx = 0; chartIdx < rates_total; chartIdx++)
   {
      //--- Find corresponding custom bar
      int customIdx = FindCustomBarByTime(chartTimes[chartIdx]);
      
      if(customIdx >= InpSMAPeriod - 1)
      {
         //--- Calculate SMA for this custom bar
         double sum = 0;
         for(int j = 0; j < InpSMAPeriod; j++)
         {
            sum += CustomBars[customIdx - j].close;
         }
         
         ValueBuffer[chartIdx] = sum / InpSMAPeriod;
         
         //--- Set color based on trend
         if(customIdx > InpSMAPeriod - 1)
         {
            double prevSum = 0;
            for(int j = 0; j < InpSMAPeriod; j++)
            {
               prevSum += CustomBars[customIdx - 1 - j].close;
            }
            double prevSMA = prevSum / InpSMAPeriod;
            ColorBuffer[chartIdx] = (ValueBuffer[chartIdx] > prevSMA) ? 0 : 1;
         }
         else
         {
            ColorBuffer[chartIdx] = 0;
         }
      }
      else
      {
         ValueBuffer[chartIdx] = 0;
         ColorBuffer[chartIdx] = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Find custom bar index by time                                    |
//+------------------------------------------------------------------+
int FindCustomBarByTime(datetime chartTime)
{
   int customBarCount = ArraySize(CustomBars);
   
   //--- Find the custom bar that contains this chart time
   for(int i = customBarCount - 1; i >= 0; i--)
   {
      datetime customBarStart = CustomBars[i].time;
      datetime customBarEnd = customBarStart + InpCustomInterval * 60;
      
      if(chartTime >= customBarStart && chartTime < customBarEnd)
         return i;
   }
   
   //--- If not found, return the latest custom bar
   return customBarCount - 1;
}

//+------------------------------------------------------------------+ 