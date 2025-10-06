//+------------------------------------------------------------------+
//|                            Consecutive Contraction Indicator.mq5 |
//|                                                        Terry Li |
//|                                                                 |
//+------------------------------------------------------------------+
#property copyright "Terry Li"
#property version   "1.10"
#property description "Detects consecutive contractions in the absolute bar body size and colors bars accordingly"
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   1

//--- plot ColorCandles
#property indicator_label1  "ColorCandles"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- color constants
#define COLOR_NONE 0     // Default color (no signal)
#define CLR_BULLISH 1    // Bullish signal color index
#define CLR_BEARISH 2    // Bearish signal color index

//--- input parameters
input int                 InpConsecutiveCount = 2;          // Number of consecutive contractions
input bool                InpSameDirection    = true;       // Require same direction for all bars
input color               InpBullishColor     = clrLime;     // Bullish signal color
input color               InpBearishColor     = clrDeepPink; // Bearish signal color
input color               InpDefaultColor     = clrNONE;     // Default bar color

//--- indicator buffers
double         BufferOpen[];            // Open prices buffer
double         BufferHigh[];            // High prices buffer
double         BufferLow[];             // Low prices buffer
double         BufferClose[];           // Close prices buffer
double         BufferColorIndex[];      // Color index buffer
double         BufferBodySizes[];       // Body sizes for calculations
double         BufferConsecutiveBullish[]; // Count of consecutive bullish signals
double         BufferConsecutiveBearish[]; // Count of consecutive bearish signals
double         BufferSignalBar[];       // Buffer to mark signal bars

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping for DRAW_COLOR_CANDLES
   SetIndexBuffer(0, BufferOpen, INDICATOR_DATA);
   SetIndexBuffer(1, BufferHigh, INDICATOR_DATA);
   SetIndexBuffer(2, BufferLow, INDICATOR_DATA);
   SetIndexBuffer(3, BufferClose, INDICATOR_DATA);
   SetIndexBuffer(4, BufferColorIndex, INDICATOR_COLOR_INDEX);
   
   //--- indicator buffers for calculations
   SetIndexBuffer(5, BufferBodySizes, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, BufferConsecutiveBullish, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, BufferConsecutiveBearish, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, BufferSignalBar, INDICATOR_CALCULATIONS);
   
   //--- setting indicator parameters
   IndicatorSetString(INDICATOR_SHORTNAME, "Consecutive Contraction (" + string(InpConsecutiveCount) + ")");
   
   //--- Set the number of colors in the color buffer
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 3); // 3 colors (default, bullish, bearish)
   
   //--- Set the colors for the color buffer
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, COLOR_NONE, InpDefaultColor);  // Default color
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, CLR_BULLISH, InpBullishColor);  // Bullish signal color
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, CLR_BEARISH, InpBearishColor);  // Bearish signal color
   
   //--- Set the drawing type and properties
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_CANDLES);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpConsecutiveCount);
   
   //--- Set buffer as timeseries (newest bars at the lowest indices)
   ArraySetAsSeries(BufferOpen, true);
   ArraySetAsSeries(BufferHigh, true);
   ArraySetAsSeries(BufferLow, true);
   ArraySetAsSeries(BufferClose, true);
   ArraySetAsSeries(BufferColorIndex, true);
   ArraySetAsSeries(BufferBodySizes, true);
   ArraySetAsSeries(BufferConsecutiveBullish, true);
   ArraySetAsSeries(BufferConsecutiveBearish, true);
   ArraySetAsSeries(BufferSignalBar, true);
   
   //--- Initialize buffers with empty values
   ArrayInitialize(BufferConsecutiveBullish, 0);
   ArrayInitialize(BufferConsecutiveBearish, 0);
   ArrayInitialize(BufferSignalBar, 0);
   ArrayInitialize(BufferColorIndex, COLOR_NONE); // Default color index
   
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
      ArrayInitialize(BufferBodySizes, 0.0);
      ArrayInitialize(BufferConsecutiveBullish, 0);
      ArrayInitialize(BufferConsecutiveBearish, 0);
      ArrayInitialize(BufferSignalBar, 0);
      ArrayInitialize(BufferColorIndex, COLOR_NONE); // Default color index
   }
   
   //--- Copy price data to our buffers and calculate body sizes for all bars that need updating
   for(int i = start; i >= 0; i--)
   {
      //--- Copy price data
      BufferOpen[i] = open[i];
      BufferHigh[i] = high[i];
      BufferLow[i] = low[i];
      BufferClose[i] = close[i];
      
      //--- Calculate absolute body size
      BufferBodySizes[i] = MathAbs(close[i] - open[i]);
      
      //--- Set default color for all bars initially
      BufferColorIndex[i] = COLOR_NONE; // Default color
      
      // Reset consecutive counters and signal markers for this bar
      BufferConsecutiveBullish[i] = 0;
      BufferConsecutiveBearish[i] = 0;
      BufferSignalBar[i] = 0;
   }
   
   //--- Now check for contraction patterns
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
      
      // Check for consecutive contractions
      if(!CheckConsecutiveContractions(BufferBodySizes, i, InpConsecutiveCount))
         continue;
      
      // We have a valid pattern, mark the signal
      SetSignal(i, isPatternBullish, rates_total);
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
//| Check if we have consecutive contractions in body size           |
//+------------------------------------------------------------------+
bool CheckConsecutiveContractions(const double &bodySizes[], int startBar, int count)
{
   for(int j = 0; j < count - 1; j++)
   {
      // For a contraction, current bar should have smaller body than previous
      if(bodySizes[startBar + j] >= bodySizes[startBar + j + 1])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Set signal based on pattern direction                            |
//+------------------------------------------------------------------+
void SetSignal(int bar, bool isBullish, int rates_total)
{
   if(isBullish)
   {
      // Update consecutive counter
      if(bar < rates_total - 1 && BufferSignalBar[bar+1] != 0 && BufferColorIndex[bar+1] == CLR_BULLISH)
         BufferConsecutiveBullish[bar] = BufferConsecutiveBullish[bar+1] + 1;
      else
         BufferConsecutiveBullish[bar] = 1;
      
      // Mark this bar as a signal bar
      BufferSignalBar[bar] = 1;
      
      // Set the color index for this bar
      BufferColorIndex[bar] = CLR_BULLISH;
   }
   else
   {
      // Update consecutive counter
      if(bar < rates_total - 1 && BufferSignalBar[bar+1] != 0 && BufferColorIndex[bar+1] == CLR_BEARISH)
         BufferConsecutiveBearish[bar] = BufferConsecutiveBearish[bar+1] + 1;
      else
         BufferConsecutiveBearish[bar] = 1;
      
      // Mark this bar as a signal bar
      BufferSignalBar[bar] = 1;
      
      // Set the color index for this bar
      BufferColorIndex[bar] = CLR_BEARISH;
   }
}
//+------------------------------------------------------------------+
