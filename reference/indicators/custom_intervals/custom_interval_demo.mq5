//+------------------------------------------------------------------+
//| Ultra Simple Custom Interval Demo - Enhanced Historical Coverage |
//| Basic working version with better historical data               |
//+------------------------------------------------------------------+
#property copyright "Simple Demo"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue

//--- Input parameters
input int CustomMinutes = 15;    // Custom interval in minutes (0 = use chart)
input int SMAPeriod = 5;         // SMA period
input int HistoryBars = 5000;    // M1 bars to get for history

//--- Buffers
double SMABuffer[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, SMABuffer, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "Simple Custom SMA");
   ArraySetAsSeries(SMABuffer, true);
   
   Print("Demo initialized - Custom Minutes: ", CustomMinutes, ", History Bars: ", HistoryBars);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   if(rates_total < SMAPeriod) return 0;
   
   // Set arrays as series
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(close, true);
   
   // If CustomMinutes is 0, use chart timeframe
   if(CustomMinutes == 0)
   {
      return CalculateNormalSMA(rates_total, prev_calculated, close);
   }
   
   // Use custom timeframe
   return CalculateCustomSMA(rates_total, prev_calculated, time, close);
}

//+------------------------------------------------------------------+
//| Calculate normal SMA on chart timeframe                         |
//+------------------------------------------------------------------+
int CalculateNormalSMA(int rates_total, int prev_calculated, const double &close[])
{
   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   
   for(int i = 0; i < limit && i < rates_total - SMAPeriod + 1; i++)
   {
      double sum = 0;
      for(int j = 0; j < SMAPeriod; j++)
      {
         sum += close[i + j];
      }
      SMABuffer[i] = sum / SMAPeriod;
   }
   
   Comment("Mode: Chart Timeframe\nSMA Period: ", SMAPeriod, "\nBars calculated: ", rates_total - SMAPeriod + 1);
   return rates_total;
}

//+------------------------------------------------------------------+
//| Calculate SMA using custom timeframe                            |
//+------------------------------------------------------------------+
int CalculateCustomSMA(int rates_total, int prev_calculated, const datetime &time[], const double &close[])
{
   // Calculate how many M1 bars we need
   // For each chart bar, we might need CustomMinutes worth of M1 data
   // Plus extra for building enough custom intervals for SMA calculation
   int neededM1Bars = MathMax(HistoryBars, rates_total * CustomMinutes + SMAPeriod * CustomMinutes);
   
   // Get M1 data - get more bars for better historical coverage
   MqlRates m1_rates[];
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, neededM1Bars, m1_rates);
   
   if(copied <= 0)
   {
      Comment("Error getting M1 data: ", GetLastError());
      return 0;
   }
   
   ArraySetAsSeries(m1_rates, true);
   
   // Build custom bars with more capacity
   double customClose[];
   datetime customTime[];
   int maxCustomBars = copied / CustomMinutes + 100; // Estimate max custom bars needed
   int customBars = BuildCustomBars(m1_rates, copied, customClose, customTime, maxCustomBars);
   
   if(customBars < SMAPeriod)
   {
      Comment("Not enough custom bars: ", customBars, " (need ", SMAPeriod, ")");
      return 0;
   }
   
   // Calculate SMA on custom bars
   double customSMA[];
   int smaCount = customBars - SMAPeriod + 1;
   ArrayResize(customSMA, smaCount);
   ArraySetAsSeries(customSMA, true);
   
   for(int i = 0; i < smaCount; i++)
   {
      double sum = 0;
      for(int j = 0; j < SMAPeriod; j++)
      {
         sum += customClose[i + j];
      }
      customSMA[i] = sum / SMAPeriod;
   }
   
   // Map to chart with better coverage
   MapToChartImproved(rates_total, time, customSMA, customTime, smaCount);
   
   Comment("Mode: Custom ", CustomMinutes, " min\n",
           "M1 bars: ", copied, "\n",
           "Custom bars: ", customBars, "\n",
           "SMA values: ", smaCount, "\n",
           "Chart bars filled: ", CountFilledBars());
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Build custom timeframe bars from M1 data                        |
//+------------------------------------------------------------------+
int BuildCustomBars(const MqlRates &m1_rates[], int m1_count, double &customClose[], 
                   datetime &customTime[], int maxBars)
{
   if(m1_count <= 0) return 0;
   
   ArrayResize(customClose, maxBars);
   ArrayResize(customTime, maxBars);
   ArraySetAsSeries(customClose, true);
   ArraySetAsSeries(customTime, true);
   
   int customCount = 0;
   datetime currentIntervalStart = 0;
   double intervalOpen = 0, intervalHigh = 0, intervalLow = 0, intervalClose = 0;
   bool hasData = false;
   
   // Process M1 bars from oldest to newest
   for(int i = m1_count - 1; i >= 0 && customCount < maxBars - 1; i--)
   {
      datetime barTime = m1_rates[i].time;
      datetime intervalStart = GetIntervalStart(barTime);
      
      if(intervalStart != currentIntervalStart)
      {
         // Save completed interval
         if(hasData)
         {
            customClose[customCount] = intervalClose;
            customTime[customCount] = currentIntervalStart;
            customCount++;
         }
         
         // Start new interval
         currentIntervalStart = intervalStart;
         intervalOpen = m1_rates[i].open;
         intervalHigh = m1_rates[i].high;
         intervalLow = m1_rates[i].low;
         intervalClose = m1_rates[i].close;
         hasData = true;
      }
      else if(hasData)
      {
         // Update current interval
         if(m1_rates[i].high > intervalHigh) intervalHigh = m1_rates[i].high;
         if(m1_rates[i].low < intervalLow) intervalLow = m1_rates[i].low;
         intervalClose = m1_rates[i].close;
      }
   }
   
   // Save last interval
   if(hasData && customCount < maxBars)
   {
      customClose[customCount] = intervalClose;
      customTime[customCount] = currentIntervalStart;
      customCount++;
   }
   
   return customCount;
}

//+------------------------------------------------------------------+
//| Get interval start time                                          |
//+------------------------------------------------------------------+
datetime GetIntervalStart(datetime barTime)
{
   int totalMinutes = (int)((barTime % 86400) / 60); // Minutes since midnight
   int intervalNum = totalMinutes / CustomMinutes;
   int startMinutes = intervalNum * CustomMinutes;
   
   datetime dayStart = barTime - (barTime % 86400);
   return dayStart + startMinutes * 60;
}

//+------------------------------------------------------------------+
//| Improved mapping to chart bars                                  |
//+------------------------------------------------------------------+
void MapToChartImproved(int rates_total, const datetime &chartTime[], const double &customSMA[], 
                       const datetime &customTime[], int smaCount)
{
   // Initialize buffer
   for(int i = 0; i < rates_total; i++)
      SMABuffer[i] = EMPTY_VALUE;
   
   // Map values with better logic
   for(int chartIdx = 0; chartIdx < rates_total; chartIdx++)
   {
      datetime cTime = chartTime[chartIdx];
      
      // Find the custom bar that this chart time should use
      int bestIdx = -1;
      
      // First try to find a custom bar that contains this time
      for(int customIdx = 0; customIdx < smaCount; customIdx++)
      {
         datetime customStart = customTime[customIdx];
         datetime customEnd = customStart + CustomMinutes * 60;
         
         if(cTime >= customStart && cTime < customEnd)
         {
            bestIdx = customIdx;
            break;
         }
      }
      
      // If not found, find the closest previous custom bar
      if(bestIdx == -1)
      {
         long minDiff = LONG_MAX;
         for(int customIdx = 0; customIdx < smaCount; customIdx++)
         {
            if(customTime[customIdx] <= cTime)
            {
               long diff = (long)(cTime - customTime[customIdx]);
               if(diff < minDiff)
               {
                  minDiff = diff;
                  bestIdx = customIdx;
               }
            }
         }
      }
      
      if(bestIdx >= 0)
      {
         SMABuffer[chartIdx] = customSMA[bestIdx];
      }
   }
}

//+------------------------------------------------------------------+
//| Count how many chart bars have SMA values                       |
//+------------------------------------------------------------------+
int CountFilledBars()
{
   int count = 0;
   int total = ArraySize(SMABuffer);
   
   for(int i = 0; i < total; i++)
   {
      if(SMABuffer[i] != EMPTY_VALUE && SMABuffer[i] != 0)
         count++;
   }
   
   return count;
} 