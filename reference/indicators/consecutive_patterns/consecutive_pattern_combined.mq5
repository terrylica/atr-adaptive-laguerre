//+------------------------------------------------------------------+
//|                           Consecutive Pattern Combined.mq5       |
//|                                                        Terry Li |
//|                                                                 |
//+------------------------------------------------------------------+
#property copyright "Terry Li"
#property version   "1.10"
#property description "Detects consecutive expansions/contractions in bar body size with both dots and colored bars"
#property indicator_chart_window
#property indicator_buffers 13
#property indicator_plots   3

//--- plot ColorCandles
#property indicator_label1  "ColorCandles"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- plot ExpansionSignals
#property indicator_label2  "ExpansionBearishSignal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDeepPink
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- plot ExpansionBullish Signal
#property indicator_label3  "ExpansionBullishSignal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- color constants
#define COLOR_NONE 0     // Default color (no signal)
#define CLR_BULLISH 1    // Bullish signal color index
#define CLR_BEARISH 2    // Bearish signal color index

//--- input parameters
// Pattern detection parameters
input group "Pattern Detection Settings"
input int                 InpConsecutiveCount = 2;          // Number of consecutive patterns
input bool                InpSameDirection    = true;       // Require same direction for all bars

// Pattern type selection
input group "Pattern Types"
input bool                InpShowExpansions   = true;       // Detect expansion patterns
input bool                InpShowContractions = true;       // Detect contraction patterns

// Visualization settings
input group "Display Settings"
input bool                InpShowDots         = true;       // Show dot signals
input bool                InpShowColorBars    = true;       // Show colored bars

// Color settings
input group "Color Settings"
input color               InpBullishColor     = clrLime;     // Bullish signal color
input color               InpBearishColor     = clrDeepPink; // Bearish signal color
input color               InpDefaultColor     = clrNONE;     // Default bar color

// Dot settings
input group "Dot Signal Settings"
input int                 InpArrowCode        = 159;         // Arrow code
input int                 InpArrowSize        = 3;           // Arrow size
input int                 InpMaxDotSize       = 14;          // Maximum dot size for consecutive signals

//--- indicator buffers
// Price and color buffers for colored candles
double         BufferOpen[];            // Open prices buffer
double         BufferHigh[];            // High prices buffer
double         BufferLow[];             // Low prices buffer
double         BufferClose[];           // Close prices buffer
double         BufferColorIndex[];      // Color index buffer

// Signal buffers for expansion dots
double         BufferExpBearishSignal[];  // Expansion bearish signal buffer
double         BufferExpBullishSignal[];  // Expansion bullish signal buffer

// Calculation buffers
double         BufferBodySizes[];       // Body sizes for calculations
double         BufferConsecutiveBullish[]; // Count of consecutive bullish signals
double         BufferConsecutiveBearish[]; // Count of consecutive bearish signals
double         BufferExpConsecutiveBullish[]; // Count of consecutive bullish expansion signals
double         BufferExpConsecutiveBearish[]; // Count of consecutive bearish expansion signals
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
   
   //--- indicator buffers for expansion signals
   SetIndexBuffer(5, BufferExpBearishSignal, INDICATOR_DATA);
   SetIndexBuffer(6, BufferExpBullishSignal, INDICATOR_DATA);
   
   //--- indicator buffers for calculations
   SetIndexBuffer(7, BufferBodySizes, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, BufferConsecutiveBullish, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, BufferConsecutiveBearish, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, BufferExpConsecutiveBullish, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, BufferExpConsecutiveBearish, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, BufferSignalBar, INDICATOR_CALCULATIONS);
   
   //--- setting indicator parameters
   IndicatorSetString(INDICATOR_SHORTNAME, "Consecutive Pattern Combined (" + string(InpConsecutiveCount) + ")");
   
   //--- Set the number of colors in the color buffer
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 3); // 3 colors (default, bullish, bearish)
   
   //--- Set the colors for the color buffer
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, COLOR_NONE, InpDefaultColor);  // Default color
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, CLR_BULLISH, InpBullishColor);  // Bullish signal color
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, CLR_BEARISH, InpBearishColor);  // Bearish signal color
   
   //--- Set the drawing type and properties
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_CANDLES);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpConsecutiveCount);
   
   //--- Set arrow properties for bearish expansion signals
   PlotIndexSetInteger(1, PLOT_ARROW, InpArrowCode);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpConsecutiveCount);
   PlotIndexSetInteger(1, PLOT_SHIFT, 0);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpBearishColor);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpArrowSize);
   
   //--- Set arrow properties for bullish expansion signals
   PlotIndexSetInteger(2, PLOT_ARROW, InpArrowCode);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpConsecutiveCount);
   PlotIndexSetInteger(2, PLOT_SHIFT, 0);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpBullishColor);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, InpArrowSize);
   
   //--- Enable/disable plots based on input settings
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowColorBars ? DRAW_COLOR_CANDLES : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, InpShowDots ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, InpShowDots ? DRAW_ARROW : DRAW_NONE);
   
   //--- Set buffer as timeseries (newest bars at the lowest indices)
   ArraySetAsSeries(BufferOpen, true);
   ArraySetAsSeries(BufferHigh, true);
   ArraySetAsSeries(BufferLow, true);
   ArraySetAsSeries(BufferClose, true);
   ArraySetAsSeries(BufferColorIndex, true);
   ArraySetAsSeries(BufferExpBearishSignal, true);
   ArraySetAsSeries(BufferExpBullishSignal, true);
   ArraySetAsSeries(BufferBodySizes, true);
   ArraySetAsSeries(BufferConsecutiveBullish, true);
   ArraySetAsSeries(BufferConsecutiveBearish, true);
   ArraySetAsSeries(BufferExpConsecutiveBullish, true);
   ArraySetAsSeries(BufferExpConsecutiveBearish, true);
   ArraySetAsSeries(BufferSignalBar, true);
   
   //--- Initialize buffers with empty values
   ArrayInitialize(BufferExpBearishSignal, EMPTY_VALUE);
   ArrayInitialize(BufferExpBullishSignal, EMPTY_VALUE);
   ArrayInitialize(BufferConsecutiveBullish, 0);
   ArrayInitialize(BufferConsecutiveBearish, 0);
   ArrayInitialize(BufferExpConsecutiveBullish, 0);
   ArrayInitialize(BufferExpConsecutiveBearish, 0);
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
      ArrayInitialize(BufferExpBearishSignal, EMPTY_VALUE);
      ArrayInitialize(BufferExpBullishSignal, EMPTY_VALUE);
      ArrayInitialize(BufferBodySizes, 0.0);
      ArrayInitialize(BufferConsecutiveBullish, 0);
      ArrayInitialize(BufferConsecutiveBearish, 0);
      ArrayInitialize(BufferExpConsecutiveBullish, 0);
      ArrayInitialize(BufferExpConsecutiveBearish, 0);
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
      
      //--- Reset signals and colors
      BufferExpBearishSignal[i] = EMPTY_VALUE;
      BufferExpBullishSignal[i] = EMPTY_VALUE;
      BufferColorIndex[i] = COLOR_NONE; // Default color
      
      // Reset consecutive counters and signal markers for this bar
      BufferConsecutiveBullish[i] = 0;
      BufferConsecutiveBearish[i] = 0;
      BufferExpConsecutiveBullish[i] = 0;
      BufferExpConsecutiveBearish[i] = 0;
      BufferSignalBar[i] = 0;
   }
   
   //--- Check for contraction patterns if enabled
   if(InpShowContractions)
   {
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
         
         // We have a valid contraction pattern, mark the signal
         SetContractionSignal(i, isPatternBullish, rates_total);
      }
   }
   
   //--- Check for expansion patterns if enabled
   if(InpShowExpansions)
   {
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
         if(!CheckConsecutiveExpansions(BufferBodySizes, i, InpConsecutiveCount))
            continue;
         
         // We have a valid expansion pattern, mark the signal
         SetExpansionSignal(i, isPatternBullish, high, low, rates_total);
      }
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
//| Check if we have consecutive expansions in body size             |
//+------------------------------------------------------------------+
bool CheckConsecutiveExpansions(const double &bodySizes[], int startBar, int count)
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
//| Set contraction signal based on pattern direction                |
//+------------------------------------------------------------------+
void SetContractionSignal(int bar, bool isBullish, int rates_total)
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
      
      // Set the color index for this bar if showing colored bars
      if(InpShowColorBars)
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
      
      // Set the color index for this bar if showing colored bars
      if(InpShowColorBars)
         BufferColorIndex[bar] = CLR_BEARISH;
   }
}

//+------------------------------------------------------------------+
//| Set expansion signal based on pattern direction                  |
//+------------------------------------------------------------------+
void SetExpansionSignal(int bar, bool isBullish, const double &high[], const double &low[], int rates_total)
{
   if(isBullish)
   {
      // Update consecutive counter
      if(bar < rates_total - 1 && BufferExpBullishSignal[bar+1] != EMPTY_VALUE)
         BufferExpConsecutiveBullish[bar] = BufferExpConsecutiveBullish[bar+1] + 1;
      else
         BufferExpConsecutiveBullish[bar] = 1;
      
      // Calculate dot size based on consecutive count
      int dotSize = InpArrowSize + (int)MathMin(BufferExpConsecutiveBullish[bar] - 1, InpMaxDotSize - InpArrowSize);
      
      // Set the arrow size and position
      if(InpShowDots)
      {
         PlotIndexSetInteger(2, PLOT_LINE_WIDTH, dotSize);
         BufferExpBullishSignal[bar] = high[bar] + (10 * Point());
      }
   }
   else
   {
      // Update consecutive counter
      if(bar < rates_total - 1 && BufferExpBearishSignal[bar+1] != EMPTY_VALUE)
         BufferExpConsecutiveBearish[bar] = BufferExpConsecutiveBearish[bar+1] + 1;
      else
         BufferExpConsecutiveBearish[bar] = 1;
      
      // Calculate dot size based on consecutive count
      int dotSize = InpArrowSize + (int)MathMin(BufferExpConsecutiveBearish[bar] - 1, InpMaxDotSize - InpArrowSize);
      
      // Set the arrow size and position
      if(InpShowDots)
      {
         PlotIndexSetInteger(1, PLOT_LINE_WIDTH, dotSize);
         BufferExpBearishSignal[bar] = low[bar] - (10 * Point());
      }
   }
}
//+------------------------------------------------------------------+
