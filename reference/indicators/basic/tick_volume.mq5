//+------------------------------------------------------------------+
//|                                               tick_volume.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Tick Volume Histogram Indicator"
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   2
//--- plot Volume
#property indicator_label1  "Volume"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrGreen,clrRed,clrDarkGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3
//--- plot MA Line
#property indicator_label2  "MA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- input parameters
input int                  InpMAPeriod       =  14;             // Moving Average Period
input double               InpThreshold      =  0.0;            // Volume change threshold
input double               InpMAScale        =  1.0;            // MA Line Scale (adjust visibility)

//--- indicator buffers
double         BufferVolume[];     // Volume values
double         BufferColors[];     // Color index for volume
double         BufferMALine[];     // Moving average line

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0, BufferVolume, INDICATOR_DATA);
   SetIndexBuffer(1, BufferColors, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufferMALine, INDICATOR_DATA);

   //--- setting indicator parameters
   IndicatorSetString(INDICATOR_SHORTNAME, "Tick Volume (" + (string)InpMAPeriod + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, 0);
   
   //--- Set minimum value to zero to prevent negative values
   IndicatorSetDouble(INDICATOR_MINIMUM, 0.0);
   
   //--- setting buffer arrays as timeseries
   ArraySetAsSeries(BufferVolume, true);
   ArraySetAsSeries(BufferColors, true);
   ArraySetAsSeries(BufferMALine, true);

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
   // Check for minimum data requirements
   if(rates_total < 2) return 0;

   // Make tick_volume array as time series
   ArraySetAsSeries(tick_volume, true);

   // Calculate starting point for calculation
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;

   // Static variable to store the previous EMA value
   static double previousEMA = 0;

   // Smoothing factor for EMA calculation
   double smoothingFactor = 2.0 / (InpMAPeriod + 1);

   // Calculate indicator values
   for (int i = start; i < rates_total && !IsStopped(); i++)
   {
      // Set volume value
      BufferVolume[rates_total - 1 - i] = (double)tick_volume[i];

      // Calculate Exponential Moving Average (EMA)
      if (i >= InpMAPeriod - 1)
      {
         double currentVolume = (double)tick_volume[i];
         double emaValue;

         if (i == InpMAPeriod - 1)
         {
            // For the first EMA calculation, use SMA as the initial value
            double maSum = 0;
            for (int j = 0; j < InpMAPeriod; j++)
            {
               maSum += (double)tick_volume[i - j];
            }
            emaValue = maSum / InpMAPeriod;
         }
         else
         {
            // Use the EMA formula for subsequent calculations
            emaValue = (currentVolume * smoothingFactor) + (previousEMA * (1 - smoothingFactor));
         }
         BufferMALine[rates_total - 1 - i] = emaValue * InpMAScale;
         previousEMA = emaValue; // Store current EMA for next calculation
      }
      else
      {
         BufferMALine[rates_total - 1 - i] = 0;
         previousEMA = 0; // Reset previous EMA when period is not enough
      }

      // Color the volume bars
      if (i > 0)
      {
         double change = (double)tick_volume[i] - (double)tick_volume[i - 1];

         if (change > InpThreshold)
            BufferColors[rates_total - 1 - i] = 0;      // Green: increasing
         else if (change < -InpThreshold)
            BufferColors[rates_total - 1 - i] = 1;      // Red: decreasing
         else
            BufferColors[rates_total - 1 - i] = 2;      // Gray: stable
      }
      else
      {
         BufferColors[rates_total - 1 - i] = 2;         // Gray for first bar
      }
   }

   return (rates_total);
}
//+------------------------------------------------------------------+