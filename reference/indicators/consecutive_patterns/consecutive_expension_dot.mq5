//+------------------------------------------------------------------+
//|                            Consecutive Expansion Indicator.mq5 |
//|                                                        Terry Li |
//|                                                                 |
//+------------------------------------------------------------------+
#property copyright "Terry Li"
#property version   "1.10"
#property description "Detects consecutive expansions in the absolute bar body size with increasing dot size for consecutive signals"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   2

//--- plot Signal
#property indicator_label1  "BearishSignal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDeepPink
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- plot Bullish Signal
#property indicator_label2  "BullishSignal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- input parameters
input int                 InpConsecutiveCount = 2;          // Number of consecutive expansions
input bool                InpSameDirection    = true;       // Require same direction for all bars
input color               InpBullishColor     = clrLime;     // Bullish signal color
input color               InpBearishColor     = clrDeepPink; // Bearish signal color
input int                 InpArrowCode        = 159;         // Arrow code
input int                 InpArrowSize        = 3;           // Arrow size
input int                 InpMaxDotSize       = 14;          // Maximum dot size for consecutive signals

//--- indicator buffers
double         BufferBearishSignal[];
double         BufferBullishSignal[];
double         BufferBodySizes[];
double         BufferConsecutiveBullish[];
double         BufferConsecutiveBearish[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0, BufferBearishSignal, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBullishSignal, INDICATOR_DATA);
   SetIndexBuffer(2, BufferBodySizes, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufferConsecutiveBullish, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufferConsecutiveBearish, INDICATOR_CALCULATIONS);
   
   //--- setting indicator parameters
   IndicatorSetString(INDICATOR_SHORTNAME, "Consecutive Expansion (" + string(InpConsecutiveCount) + ")");
   
   //--- Set arrow properties for bearish signals
   PlotIndexSetInteger(0, PLOT_ARROW, InpArrowCode);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpConsecutiveCount);
   PlotIndexSetInteger(0, PLOT_SHIFT, 0);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBearishColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpArrowSize);
   
   //--- Set arrow properties for bullish signals
   PlotIndexSetInteger(1, PLOT_ARROW, InpArrowCode);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpConsecutiveCount);
   PlotIndexSetInteger(1, PLOT_SHIFT, 0);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpBullishColor);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpArrowSize);
   
   //--- Set buffer as timeseries
   ArraySetAsSeries(BufferBearishSignal, true);
   ArraySetAsSeries(BufferBullishSignal, true);
   ArraySetAsSeries(BufferBodySizes, true);
   ArraySetAsSeries(BufferConsecutiveBullish, true);
   ArraySetAsSeries(BufferConsecutiveBearish, true);
   
   //--- Initialize buffers with empty values
   ArrayInitialize(BufferBearishSignal, EMPTY_VALUE);
   ArrayInitialize(BufferBullishSignal, EMPTY_VALUE);
   ArrayInitialize(BufferConsecutiveBullish, 0);
   ArrayInitialize(BufferConsecutiveBearish, 0);
   
   //--- initialization done
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
   //--- Check for minimum bars required
   if(rates_total <= InpConsecutiveCount)
      return(0);
      
   //--- Make arrays as timeseries (newest bars at the lowest indices)
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   
   //--- Calculate the first bar to start from
   int start = (prev_calculated == 0) ? rates_total - 1 : prev_calculated - 1;
   
   //--- Initialize buffers if this is the first calculation
   if(prev_calculated == 0)
   {
      ArrayInitialize(BufferBearishSignal, EMPTY_VALUE);
      ArrayInitialize(BufferBullishSignal, EMPTY_VALUE);
      ArrayInitialize(BufferBodySizes, 0.0);
      ArrayInitialize(BufferConsecutiveBullish, 0);
      ArrayInitialize(BufferConsecutiveBearish, 0);
   }
   
   //--- Calculate body sizes for all bars that need updating
   for(int i = start; i >= 1; i--)
   {
      //--- Calculate absolute body size
      BufferBodySizes[i] = MathAbs(close[i] - open[i]);
      BufferBearishSignal[i] = EMPTY_VALUE; // Reset the bearish signal
      BufferBullishSignal[i] = EMPTY_VALUE; // Reset the bullish signal
      
      // Reset consecutive counters for this bar
      BufferConsecutiveBullish[i] = 0;
      BufferConsecutiveBearish[i] = 0;
   }
   
   //--- Now check for expansion patterns
   for(int i = 1; i < rates_total - InpConsecutiveCount; i++)
   {
      //--- Skip bars that don't have enough preceding bars
      if(i + InpConsecutiveCount >= rates_total)
         continue;
      
      // Determine pattern direction based on the first signaling bar
      bool isPatternBullish = close[i] > open[i];
      
      // Check for same direction if required
      if(InpSameDirection && !CheckSameDirection(open, close, i, InpConsecutiveCount, isPatternBullish))
         continue;
      
      // Check for consecutive expansions
      if(!CheckConsecutiveContractions(BufferBodySizes, i, InpConsecutiveCount))
         continue;
      
      // We have a valid pattern, mark the signal
      SetSignal(i, isPatternBullish, high, low, rates_total);
   }
   
   //--- return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Check if all bars in the pattern have the same direction         |
//+------------------------------------------------------------------+
bool CheckSameDirection(const double &open[], const double &close[], int startBar, int count, bool isBullish)
{
   for(int j = 1; j < count; j++)
   {
      bool isCurrentBarBullish = close[startBar + j] > open[startBar + j];
      if(isCurrentBarBullish != isBullish)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if we have consecutive expansions in body size             |
//+------------------------------------------------------------------+
bool CheckConsecutiveContractions(const double &bodySizes[], int startBar, int count)
{
   for(int j = 0; j < count - 1; j++)
   {
      // For an expansion, current bar should have larger body than previous
      if(bodySizes[startBar + j] <= bodySizes[startBar + j + 1])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Set signal based on pattern direction                            |
//+------------------------------------------------------------------+
void SetSignal(int bar, bool isBullish, const double &high[], const double &low[], int rates_total)
{
   if(isBullish)
   {
      // Update consecutive counter
      if(bar < rates_total - 1 && BufferBullishSignal[bar+1] != EMPTY_VALUE)
         BufferConsecutiveBullish[bar] = BufferConsecutiveBullish[bar+1] + 1;
      else
         BufferConsecutiveBullish[bar] = 1;
      
      // Calculate dot size based on consecutive count
      int dotSize = InpArrowSize + (int)MathMin(BufferConsecutiveBullish[bar] - 1, InpMaxDotSize - InpArrowSize);
      
      // Set the arrow size and position
      PlotIndexSetInteger(1, PLOT_LINE_WIDTH, dotSize);
      BufferBullishSignal[bar] = high[bar] + (10 * Point());
      // Alert("Bullish Consecutive Expansion Signal at bar ", bar); // Removed bullish alert
   }
   else
   {
      // Update consecutive counter
      if(bar < rates_total - 1 && BufferBearishSignal[bar+1] != EMPTY_VALUE)
         BufferConsecutiveBearish[bar] = BufferConsecutiveBearish[bar+1] + 1;
      else
         BufferConsecutiveBearish[bar] = 1;
      
      // Calculate dot size based on consecutive count
      int dotSize = InpArrowSize + (int)MathMin(BufferConsecutiveBearish[bar] - 1, InpMaxDotSize - InpArrowSize);
      
      // Set the arrow size and position
      PlotIndexSetInteger(0, PLOT_LINE_WIDTH, dotSize);
      BufferBearishSignal[bar] = low[bar] - (10 * Point());
      // Alert("Bearish Consecutive Expansion Signal at bar ", bar); // Removed bearish alert
   }
}
//+------------------------------------------------------------------+
