//+------------------------------------------------------------------+
//|                                Bollinger_Band_Width.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                                 https://mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://mql5.com"
#property version   "1.00"
#property description "Bollinger Band Width - vertical distance between upper and lower bands"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   1
//--- plot BB Width
#property indicator_label1  "BB Width"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrLightGreen,clrGreen,clrDarkGreen,clrLightCoral,clrRed,clrDarkRed,clrDarkGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- input parameters
input uint                 InpPeriodBB       =  20;            // BB period
input double               InpDeviation      =  2.0;           // BB deviation
input ENUM_APPLIED_PRICE   InpAppliedPrice   =  PRICE_CLOSE;   // Applied price
input uint                 InpHistoryBars    =  999;           // Historical bars to analyze
input uint                 InpMaxIncreases   =  123;           // Max increasing changes to collect
input uint                 InpMaxDecreases   =  123;           // Max decreasing changes to collect

//--- indicator buffers
double         BufferBBWidth[];
double         BufferColors[];
double         BufferMA[];
double         BufferDev[];
double         BufferPctChanges[];  // To store percent changes for analysis

//--- global variables
double         deviation;
int            period_bb;
int            handle_ma;
int            handle_dev;
int            history_bars;
int            max_increases;
int            max_decreases;

// Color indices
#define COLOR_LIGHT_GREEN    0  // Slow increase
#define COLOR_MEDIUM_GREEN   1  // Medium increase
#define COLOR_DARK_GREEN     2  // Fast increase
#define COLOR_LIGHT_RED      3  // Slow decrease
#define COLOR_MEDIUM_RED     4  // Medium decrease
#define COLOR_DARK_RED       5  // Fast decrease
#define COLOR_GRAY           6  // Unchanged

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- set global variables
   period_bb=int(InpPeriodBB<1 ? 1 : InpPeriodBB);
   deviation=InpDeviation;
   history_bars=int(InpHistoryBars<10 ? 10 : InpHistoryBars);
   max_increases=int(InpMaxIncreases<5 ? 5 : InpMaxIncreases);
   max_decreases=int(InpMaxDecreases<5 ? 5 : InpMaxDecreases);

//--- indicator buffers mapping
   SetIndexBuffer(0,BufferBBWidth,INDICATOR_DATA);
   SetIndexBuffer(1,BufferColors,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,BufferMA,INDICATOR_CALCULATIONS);
   SetIndexBuffer(3,BufferDev,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,BufferPctChanges,INDICATOR_CALCULATIONS);

//--- setting indicator parameters
   IndicatorSetString(INDICATOR_SHORTNAME,"BB Width ("+(string)period_bb+","+DoubleToString(deviation,2)+")");
   IndicatorSetInteger(INDICATOR_DIGITS,Digits());

//--- setting plot buffer parameters
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_COLOR_HISTOGRAM);
   PlotIndexSetInteger(0,PLOT_LINE_STYLE,STYLE_SOLID);
   PlotIndexSetInteger(0,PLOT_LINE_WIDTH,2);
   PlotIndexSetInteger(0,PLOT_SHOW_DATA,true);
   
   // Set colors for different states
   PlotIndexSetInteger(0,PLOT_COLOR_INDEXES,7);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,COLOR_LIGHT_GREEN,clrLightGreen);     // Slow increase
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,COLOR_MEDIUM_GREEN,clrGreen);         // Medium increase
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,COLOR_DARK_GREEN,clrDarkGreen);       // Fast increase
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,COLOR_LIGHT_RED,clrLightCoral);       // Slow decrease
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,COLOR_MEDIUM_RED,clrRed);             // Medium decrease
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,COLOR_DARK_RED,clrDarkRed);           // Fast decrease
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,COLOR_GRAY,clrDarkGray);              // Unchanged

//--- setting buffer arrays as timeseries
   ArraySetAsSeries(BufferBBWidth,true);
   ArraySetAsSeries(BufferColors,true);
   ArraySetAsSeries(BufferMA,true);
   ArraySetAsSeries(BufferDev,true);
   ArraySetAsSeries(BufferPctChanges,true);

//--- create handles
   ResetLastError();
   handle_ma=iMA(NULL,PERIOD_CURRENT,period_bb,0,MODE_SMA,InpAppliedPrice);
   if(handle_ma==INVALID_HANDLE)
     {
      Print("The iMA(",(string)period_bb,") object was not created: Error ",GetLastError());
      return INIT_FAILED;
     }
   handle_dev=iStdDev(NULL,PERIOD_CURRENT,period_bb,0,MODE_SMA,InpAppliedPrice);
   if(handle_dev==INVALID_HANDLE)
     {
      Print("The iStdDev(",(string)period_bb,") object was not created: Error ",GetLastError());
      return INIT_FAILED;
     }
//---
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
//--- Проверка и расчёт количества просчитываемых баров
   if(rates_total<4 || Point()==0) return 0;

//--- Проверка и расчёт количества просчитываемых баров
   int limit=rates_total-prev_calculated;
   if(limit>1)
     {
      limit=rates_total-2;
      ArrayInitialize(BufferBBWidth,0);
      ArrayInitialize(BufferColors,COLOR_GRAY);    // Default to gray
      ArrayInitialize(BufferMA,0);
      ArrayInitialize(BufferDev,0);
      ArrayInitialize(BufferPctChanges,0);
     }

//--- Подготовка данных
   int count=(limit>1 ? rates_total : 1),copied=0;
   copied=CopyBuffer(handle_ma,0,0,count,BufferMA);
   if(copied!=count) return 0;
   copied=CopyBuffer(handle_dev,0,0,count,BufferDev);
   if(copied!=count) return 0;

//--- Расчёт индикатора
   for(int i=limit; i>=0 && !IsStopped(); i--)
     {
      if(BufferMA[i]!=0)
        {
         //--- Calculate the absolute Bollinger Band width (vertical distance between bands)
         BufferBBWidth[i] = 2 * deviation * BufferDev[i];
        }
      else
        {
         BufferBBWidth[i]=0;
        }
        
      //--- Calculate percent change compared to previous bar
      if(i < rates_total-1 && BufferBBWidth[i+1] != 0)
        {
         BufferPctChanges[i] = (BufferBBWidth[i] - BufferBBWidth[i+1]) / BufferBBWidth[i+1] * 100.0;
        }
      else
        {
         BufferPctChanges[i] = 0;
        }
     }
   
   //--- Now we have calculated all the BB width values, apply adaptive color scaling
   //--- Only process if we have enough bars for our lookback
   if(rates_total > history_bars)
     {
      //--- Arrays to collect increasing and decreasing changes
      double increasingChanges[];
      double decreasingChanges[];
      ArrayResize(increasingChanges, max_increases);
      ArrayResize(decreasingChanges, max_decreases);
      ArrayInitialize(increasingChanges, 0);
      ArrayInitialize(decreasingChanges, 0);
      
      int increasingCount = 0;
      int decreasingCount = 0;
      
      //--- Collect the most recent increases and decreases within master lookback
      for(int i=0; i<history_bars && i<rates_total-1; i++)
        {
         if(BufferPctChanges[i] > 0) // Increasing
           {
            if(increasingCount < max_increases)
              {
               increasingChanges[increasingCount] = BufferPctChanges[i];
               increasingCount++;
              }
           }
         else if(BufferPctChanges[i] < 0) // Decreasing
           {
            if(decreasingCount < max_decreases)
              {
               decreasingChanges[decreasingCount] = MathAbs(BufferPctChanges[i]); // Store absolute value
               decreasingCount++;
              }
           }
        }
      
      //--- Sort the arrays to find boundaries
      if(increasingCount > 0)
        {
         ArraySort(increasingChanges);
         // Reverse to get descending order (MQL5 sorts ascending by default)
         for(int i=0; i<increasingCount/2; i++)
           {
            double temp = increasingChanges[i];
            increasingChanges[i] = increasingChanges[increasingCount-1-i];
            increasingChanges[increasingCount-1-i] = temp;
           }
        }
      
      if(decreasingCount > 0)
        {
         ArraySort(decreasingChanges);
         // Reverse to get descending order (MQL5 sorts ascending by default)
         for(int i=0; i<decreasingCount/2; i++)
           {
            double temp = decreasingChanges[i];
            decreasingChanges[i] = decreasingChanges[decreasingCount-1-i];
            decreasingChanges[decreasingCount-1-i] = temp;
           }
        }
      
      //--- Determine thresholds for increasing (3 ranges)
      double increaseThreshold1 = 0, increaseThreshold2 = 0;
      if(increasingCount >= 3)
        {
         increaseThreshold1 = increasingChanges[increasingCount/3];
         increaseThreshold2 = increasingChanges[2*increasingCount/3];
        }
      else if(increasingCount > 0)
        {
         increaseThreshold1 = increaseThreshold2 = increasingChanges[0] / 2;
        }
      
      //--- Determine thresholds for decreasing (3 ranges)
      double decreaseThreshold1 = 0, decreaseThreshold2 = 0;
      if(decreasingCount >= 3)
        {
         decreaseThreshold1 = decreasingChanges[decreasingCount/3];
         decreaseThreshold2 = decreasingChanges[2*decreasingCount/3];
        }
      else if(decreasingCount > 0)
        {
         decreaseThreshold1 = decreaseThreshold2 = decreasingChanges[0] / 2;
        }
      
      //--- Apply color based on thresholds
      for(int i=0; i<rates_total-1; i++)
        {
         if(MathAbs(BufferPctChanges[i]) < 0.0001) // Practically unchanged
           {
            BufferColors[i] = COLOR_GRAY;
           }
         else if(BufferPctChanges[i] > 0) // Increasing
           {
            if(BufferPctChanges[i] > increaseThreshold1)
               BufferColors[i] = COLOR_DARK_GREEN;     // Fast increase
            else if(BufferPctChanges[i] > increaseThreshold2)
               BufferColors[i] = COLOR_MEDIUM_GREEN;   // Medium increase
            else
               BufferColors[i] = COLOR_LIGHT_GREEN;    // Slow increase
           }
         else // Decreasing
           {
            double absChange = MathAbs(BufferPctChanges[i]);
            if(absChange > decreaseThreshold1)
               BufferColors[i] = COLOR_DARK_RED;       // Fast decrease
            else if(absChange > decreaseThreshold2)
               BufferColors[i] = COLOR_MEDIUM_RED;     // Medium decrease
            else
               BufferColors[i] = COLOR_LIGHT_RED;      // Slow decrease
           }
        }
     }
     
   //--- For the very last bar just use a simple comparison if it's the first calculation
   if(prev_calculated == 0 && rates_total > 1)
     {
      if(MathAbs(BufferPctChanges[0]) < 0.0001)
         BufferColors[0] = COLOR_GRAY;
      else if(BufferPctChanges[0] > 0)
         BufferColors[0] = COLOR_MEDIUM_GREEN;
      else
         BufferColors[0] = COLOR_MEDIUM_RED;
     }

//--- return value of prev_calculated for next call
   return(rates_total);
  }
//+------------------------------------------------------------------+ 