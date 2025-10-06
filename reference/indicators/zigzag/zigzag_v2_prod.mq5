//+------------------------------------------------------------------+
//|                                                  ZigzagColor.mq5 |
//|                             Copyright 2000-2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| ALGORITHM OVERVIEW:                                              |
//+------------------------------------------------------------------+
// The ZigZag indicator identifies significant price reversals while filtering
// out minor price movements. The algorithm works as follows:
//
// 1. IDENTIFICATION OF EXTREME POINTS:
//    - Peaks (high points) and bottoms (low points) are identified
//    - Points must be separated by at least InpBackstep bars
//    - Price change must exceed InpDeviation points
//
// 2. ZIGZAG CONSTRUCTION:
//    - Identified extremes are connected to form the zigzag
//    - Each zigzag leg connects alternating peaks and bottoms
//    - The algorithm tracks high/low extreme positions and values
//
// 3. CONFIRMATION DISPLAY (optional):
//    - Arrows can be shown where a reversal is confirmed by a subsequent extreme
//    - Peak confirmations appear after a bottom is found
//    - Bottom confirmations appear after a peak is found
//
// 4. REPAINTING PREVENTION (optional):
//    - The most recent 1-2 zigzag legs can be hidden until confirmed
//    - This prevents the indicator from "repainting" historical signals
//
// PORTING NOTES:
// - The indicator uses multiple buffer arrays which need to be managed together
// - The search state machine (SEARCH_FIRST_EXTREMUM/NEXT_PEAK/NEXT_BOTTOM) is critical
// - When porting to other languages, maintain separate arrays for peaks/bottoms
// - Pay close attention to the order of operations in the main algorithm
//+------------------------------------------------------------------+

//--- indicator settings
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   3
#property indicator_type1   DRAW_COLOR_ZIGZAG
#property indicator_color1  clrLimeGreen,clrPurple  // Define default zigzag colors here
#property indicator_width1  2                 // Make lines thicker
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrMagenta        // Default color for peak confirmations
#property indicator_width2  1                 // Make arrows bigger
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCyan           // Default color for bottom confirmations
#property indicator_width3  1                 // Make arrows bigger
#property indicator_type4   DRAW_SECTION
#property indicator_color4  clrMagenta        // Default color for peak confirmation section
#property indicator_width4  1
#property indicator_style4  STYLE_DASH        // Dashed line style for better visibility
#property indicator_type5   DRAW_SECTION
#property indicator_color5  clrCyan           // Default color for bottom confirmation section
#property indicator_width5  1
#property indicator_style5  STYLE_DASH        // Dashed line style for better visibility
//--- input parameters
input int InpDepth    =12;  // Depth
input int InpDeviation=5;   // Deviation
input int InpBackstep =3;   // Back Step
input bool InpNoRepaint=true; // Prevent last leg repainting
input bool InpShowConfirmation=true; // Show confirmation arrows at reversal points
input int InpArrowShift=-17; // `-`: arrow away from price; `+`: arrow toward price
input color InpUpColor=clrDarkOliveGreen;   // Uptrend color
input color InpDownColor=clrSaddleBrown;    // Downtrend color
input bool InpUpdateOnNewBarOnly=true; // Calculate only on bar completion

//--- indicator buffers
double ZigzagPeakBuffer[];
double ZigzagBottomBuffer[];
double HighMapBuffer[];
double LowMapBuffer[];
double ColorBuffer[];
double ConfirmPeakBuffer[];    // Buffer for confirmed peaks
double ConfirmBottomBuffer[];  // Buffer for confirmed bottoms

//--- global variables
int ExtRecalc=3; // recounting's depth
datetime g_last_bar_time = 0; // For tracking new bar formation

// ZigZag state management enum - defines what type of extreme point we're looking for
enum EnSearchMode
  {
   SEARCH_FIRST_EXTREMUM = 0,  // Initial state: searching for the first extremum (peak or bottom)
   SEARCH_NEXT_PEAK = 1,       // Looking for the next peak (after finding a bottom)
   SEARCH_NEXT_BOTTOM = -1     // Looking for the next bottom (after finding a peak)
  };

// Constants for clarity when porting to other languages
#define TREND_UP 0    // Index for uptrend color - needed for ColorBuffer assignments
#define TREND_DOWN 1  // Index for downtrend color - needed for ColorBuffer assignments

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void OnInit()
  {
   SetupBuffers();
   SetupVisualElements();
   SetupLabels();
   
   // Set calculation mode to update only on bar completion if requested
   // Using the official approach with the correct enum name
#ifdef CALCULATIONS_ONLY_ON_BARS
   // If the constant is defined in this version, use it
   IndicatorSetInteger(CALCULATIONS_ONLY_ON_BARS, InpUpdateOnNewBarOnly);
#endif
  }

//+------------------------------------------------------------------+
//| Setup indicator buffers and mapping                              |
//+------------------------------------------------------------------+
void SetupBuffers()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0,ZigzagPeakBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,ZigzagBottomBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,ColorBuffer,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(3,HighMapBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,LowMapBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,ConfirmPeakBuffer,INDICATOR_DATA);
   SetIndexBuffer(6,ConfirmBottomBuffer,INDICATOR_DATA);
   //--- set accuracy
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
}

//+------------------------------------------------------------------+
//| Setup visual elements like arrows, colors and line styles        |
//+------------------------------------------------------------------+
void SetupVisualElements()
{
   //--- set arrow codes
   PlotIndexSetInteger(1,PLOT_ARROW,233); // Up arrow for peak confirmations
   PlotIndexSetInteger(2,PLOT_ARROW,234); // Down arrow for bottom confirmations
   //--- set arrow vertical shift in pixels
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,InpArrowShift); // Shift for peaks
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,-InpArrowShift); // Negative shift for bottoms to move up
   
   //--- Set ZigZag colors - critical for correct color display
   PlotIndexSetInteger(0,PLOT_COLOR_INDEXES,2);          // Number of colors
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,0,InpUpColor);  // Uptrend color (index 0)
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,1,InpDownColor);// Downtrend color (index 1)
   
   // Set up arrow colors to match opposite trend colors
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,0,InpDownColor);  // Up arrows match downtrend color
   PlotIndexSetInteger(2,PLOT_LINE_COLOR,0,InpUpColor);    // Down arrows match uptrend color
   PlotIndexSetInteger(4,PLOT_LINE_COLOR,0,InpDownColor);  // Peak confirmation lines match downtrend color
   PlotIndexSetInteger(5,PLOT_LINE_COLOR,0,InpUpColor);    // Bottom confirmation lines match uptrend color

   // Hide or show the confirmation arrows based on InpShowConfirmation parameter
   if(!InpShowConfirmation)
     {
      // Hide arrow plots when confirmation display is disabled
      PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetInteger(2,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetInteger(4,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetInteger(5,PLOT_DRAW_TYPE,DRAW_NONE);
     }
   else
     {
      // Make sure arrows are visible when enabled
      PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_ARROW);
      PlotIndexSetInteger(2,PLOT_DRAW_TYPE,DRAW_ARROW);
      // Make sure arrow codes are set correctly
      PlotIndexSetInteger(1,PLOT_ARROW,233); // Up arrow for peak confirmations
      PlotIndexSetInteger(2,PLOT_ARROW,234); // Down arrow for bottom confirmations
      // Show section lines
      PlotIndexSetInteger(4,PLOT_DRAW_TYPE,DRAW_SECTION);
      PlotIndexSetInteger(5,PLOT_DRAW_TYPE,DRAW_SECTION);
     }
   
   //--- set an empty value for data plots
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0.0);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,0.0);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,0.0);
}

//+------------------------------------------------------------------+
//| Setup indicator name and labels                                  |
//+------------------------------------------------------------------+
void SetupLabels()
{
   //--- name for DataWindow and indicator subwindow label
   string short_name=StringFormat("ZigZagColor(%d,%d,%d)",InpDepth,InpDeviation,InpBackstep);
   IndicatorSetString(INDICATOR_SHORTNAME,short_name);
   PlotIndexSetString(0,PLOT_LABEL,short_name);
   PlotIndexSetString(1,PLOT_LABEL,short_name+" Peak Confirmations");
   PlotIndexSetString(2,PLOT_LABEL,short_name+" Bottom Confirmations");
}

// Function declaration to be implemented in helper section
bool IsNewBar();

//+------------------------------------------------------------------+
//| ZigZag calculation                                               |
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
   // Check if we should only update on new bars
   if(InpUpdateOnNewBarOnly && prev_calculated > 0)
   {
      // If user has selected to update only on bar completion and this is not a new bar
      if(!IsNewBar())
         return(prev_calculated); // Skip calculation on this tick
   }
     
   if(rates_total<100)
      return(0);

   // Initialize calculation variables and starting position
   int start=0;
   int extreme_search=SEARCH_FIRST_EXTREMUM;
   double cur_high=0,cur_low=0,last_high=0,last_low=0;
   int last_high_pos=0,last_low_pos=0;
   
   // Perform initialization based on calculation state
   if(!InitializeCalculation(rates_total, prev_calculated, high, low, 
                             start, extreme_search, cur_high, cur_low, 
                             last_high, last_low, last_high_pos, last_low_pos))
      return rates_total;

   // Find high and low extremes
   FindExtremes(start, rates_total, high, low, last_high, last_low);

   //--- set last values
   if(extreme_search==SEARCH_FIRST_EXTREMUM) // undefined values
     {
      last_low=0;
      last_high=0;
     }
   else
     {
      last_low=cur_low;
      last_high=cur_high;
     }
   
   // Select extreme points to form the ZigZag pattern
   SelectExtremePoints(start, rates_total, high, low, extreme_search,
                     last_high, last_low, last_high_pos, last_low_pos);

   // Handle non-repainting and confirmation visualizations
   if(InpNoRepaint || InpShowConfirmation)
     {
      HandleNonRepaintingAndConfirmation(rates_total, high, low);
     }

//--- return value of prev_calculated for next call
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Handle non-repainting and confirmation display                   |
//+------------------------------------------------------------------+
void HandleNonRepaintingAndConfirmation(const int rates_total,
                                       const double &high[],
                                       const double &low[])
{
    // Define a struct to store extreme point information
    struct ExtremePoint 
    {
       int position;     // Bar position
       bool isPeak;      // True if peak, false if bottom
    };
    
    // Find the last three extremes (need three to confirm the middle one)
    int lastExtremesCount = 3;  // We need to find this many recent extremes
    ExtremePoint extremes[3];   // Array to store the last three extremes
    
    // Initialize extreme points array
    for(int i=0; i<lastExtremesCount; i++) {
       extremes[i].position = -1; // -1 means not found yet
       extremes[i].isPeak = false;
    }
    
    // STEP 1: Find positions of the last three extremes by scanning backward
    int extremeCount = 0;
    for(int i=rates_total-1; i>=0 && extremeCount < lastExtremesCount; i--)
     {
       bool isExtremePoint = (ZigzagPeakBuffer[i] != 0 || ZigzagBottomBuffer[i] != 0);
       
       if(isExtremePoint)
         {
          // Record this extreme point's details
          extremes[extremeCount].position = i;
          extremes[extremeCount].isPeak = (ZigzagPeakBuffer[i] != 0);
          extremeCount++;
         }
     }
    
    // STEP 2: Process zigzag points for confirmation markers if enabled
    if(InpShowConfirmation)
      {
       ProcessConfirmationMarkers(rates_total, high, low);
      }
    
    // STEP 3: Handle non-repainting if enabled
    if(InpNoRepaint && extremeCount > 0)
      {
       // Pass the array of positions directly rather than the struct array
       int positions[3];
       bool isPeaks[3];
       
       for(int i=0; i<extremeCount; i++) {
          positions[i] = extremes[i].position;
          isPeaks[i] = extremes[i].isPeak;
       }
       
       // Arrays are passed by reference in MQL5
       HandleNonRepainting(positions, isPeaks, extremeCount, rates_total);
      }
}

//+------------------------------------------------------------------+
//| Process confirmation markers at zigzag reversal points           |
//+------------------------------------------------------------------+
void ProcessConfirmationMarkers(const int rates_total,
                              const double &high[],
                              const double &low[])
{
   // First clear all confirmation buffers
   for(int i=0; i<rates_total; i++)
     {
      ConfirmPeakBuffer[i] = 0;
      ConfirmBottomBuffer[i] = 0;
     }
      
   // Scan all bars to find zigzag points that are followed by a reversal
   for(int i=0; i<rates_total-1; i++)
     {
      // STEP 1: Find and mark peak confirmations
      if(ZigzagPeakBuffer[i] != 0)
        {
         // Look ahead for a bottom that confirms this peak
         for(int j=i+1; j<rates_total; j++)
           {
            bool hasFoundConfirmingBottom = (ZigzagBottomBuffer[j] != 0);
            
            if(hasFoundConfirmingBottom)
              {
               // Mark confirmation of peak with an up arrow at the reversal point
               ConfirmPeakBuffer[j] = high[j];
               break; // Stop after finding the first confirmation
              }
           }
        }
      
      // STEP 2: Find and mark bottom confirmations
      else if(ZigzagBottomBuffer[i] != 0)
        {
         // Look ahead for a peak that confirms this bottom
         for(int j=i+1; j<rates_total; j++)
           {
            bool hasFoundConfirmingPeak = (ZigzagPeakBuffer[j] != 0);
            
            if(hasFoundConfirmingPeak)
              {
               // Mark confirmation of bottom with a down arrow at the reversal point
               ConfirmBottomBuffer[j] = low[j];
               break; // Stop after finding the first confirmation
              }
           }
        }
     }
}

//+------------------------------------------------------------------+
//| Remove unconfirmed zigzag points to prevent repainting           |
//+------------------------------------------------------------------+
void HandleNonRepainting(const int &positions[], 
                       const bool &isPeaks[], 
                       const int extremeCount, 
                       const int rates_total)
{
   // We need at least two extreme points to apply non-repainting
   if(extremeCount < 2)
      return;
      
   int lastExtremePos = positions[0];
   int prevExtremePos = positions[1];
   int thirdExtremePos = (extremeCount > 2) ? positions[2] : -1;
   
   // STEP 1: Always clear the most recent extreme as it's not confirmed yet
   if(lastExtremePos >= 0)
     {
      // Clear the last extreme point
      ZigzagPeakBuffer[lastExtremePos] = 0;
      ZigzagBottomBuffer[lastExtremePos] = 0;
      
      // Also clear the zigzag line connecting to the previous extreme
      for(int i=prevExtremePos+1; i<lastExtremePos; i++)
        {
         ZigzagPeakBuffer[i] = 0;
         ZigzagBottomBuffer[i] = 0;
        }
     }
   
   // STEP 2: If we don't have three extremes, the second-to-last one is also not confirmed
   if(thirdExtremePos == -1 && prevExtremePos >= 0)
     {
      // Clear the previous extreme point
      ZigzagPeakBuffer[prevExtremePos] = 0;
      ZigzagBottomBuffer[prevExtremePos] = 0;
      
      // Scan backwards to find the previous extreme before our third one
      int priorExtremePos = -1;
      for(int i=prevExtremePos-1; i>=0; i--)
        {
         if(ZigzagPeakBuffer[i] != 0 || ZigzagBottomBuffer[i] != 0)
           {
            priorExtremePos = i;
            break;
           }
        }
      
      // Clear connecting line if we found a prior extreme
      if(priorExtremePos >= 0)
        {
         for(int i=priorExtremePos+1; i<prevExtremePos; i++)
           {
            ZigzagPeakBuffer[i] = 0;
            ZigzagBottomBuffer[i] = 0;
           }
        }
     }
}

//+------------------------------------------------------------------+
//| Select extreme points to form the ZigZag pattern                 |
//+------------------------------------------------------------------+
void SelectExtremePoints(const int start, 
                        const int rates_total, 
                        const double &high[], 
                        const double &low[],
                        int &extreme_search,
                        double &last_high, 
                        double &last_low, 
                        int &last_high_pos,
                        int &last_low_pos)
{
   //--- final selection of extreme points for ZigZag
   for(int shift=start; shift<rates_total && !IsStopped(); shift++)
     {
      // Process bars based on our current search mode
      switch(extreme_search)
        {
         //--- Case 1: Initial search for the first extreme point of any type
         case SEARCH_FIRST_EXTREMUM:
           {
            // Only process if we haven't found any extremes yet
            if(last_low==0 && last_high==0)
              {
               // Check if current bar is a high extreme (peak)
               bool isHighExtreme = (HighMapBuffer[shift] != 0);
               if(isHighExtreme)
                 {
                  // Record this as our first peak
                  last_high = high[shift];
                  last_high_pos = shift;
                  
                  // Now we'll start looking for a bottom next
                  extreme_search = SEARCH_NEXT_BOTTOM;
                  
                  // Mark this point on the zigzag line
                  ZigzagPeakBuffer[shift] = last_high;
                  ColorBuffer[shift] = TREND_UP;
                 }
               
               // Check if current bar is a low extreme (bottom)
               bool isLowExtreme = (LowMapBuffer[shift] != 0);
               if(isLowExtreme)
                 {
                  // Record this as our first bottom
                  last_low = low[shift];
                  last_low_pos = shift;
                  
                  // Now we'll start looking for a peak next
                  extreme_search = SEARCH_NEXT_PEAK;
                  
                  // Mark this point on the zigzag line
                  ZigzagBottomBuffer[shift] = last_low;
                  ColorBuffer[shift] = TREND_DOWN;
                 }
              }
            break;
           }
         
         //--- Case 2: We found a bottom, now looking for next peak or a better bottom
         case SEARCH_NEXT_PEAK:
           {
            // SCENARIO 1: Check if we've found a better (lower) bottom than our last one
            bool isNewLowerBottom = (
               LowMapBuffer[shift] != 0.0 &&         // Is a valid low extreme
               LowMapBuffer[shift] < last_low &&     // Is lower than our last one
               HighMapBuffer[shift] == 0.0           // Is not also a high point
            );
            
            if(isNewLowerBottom)
              {
               // Remove the old bottom from zigzag line
               ZigzagBottomBuffer[last_low_pos] = 0.0;
               
               // Update our tracking to this better (lower) bottom
               last_low_pos = shift;
               last_low = LowMapBuffer[shift];
               
               // Mark new bottom point on zigzag line
               ZigzagBottomBuffer[shift] = last_low;
               ColorBuffer[shift] = TREND_DOWN;
              }
            
            // SCENARIO 2: Check if we've found a peak to connect to
            bool isValidPeak = (
               HighMapBuffer[shift] != 0.0 &&        // Is a valid high extreme
               LowMapBuffer[shift] == 0.0            // Is not also a low point
            );
            
            if(isValidPeak)
              {
               // Record this peak
               last_high = HighMapBuffer[shift];
               last_high_pos = shift;
               
               // Mark this point on zigzag line
               ZigzagPeakBuffer[shift] = last_high;
               ColorBuffer[shift] = TREND_UP;
               
               // Now switch to looking for the next bottom
               extreme_search = SEARCH_NEXT_BOTTOM;
              }
            break;
           }
         
         //--- Case 3: We found a peak, now looking for next bottom or a better peak
         case SEARCH_NEXT_BOTTOM:
           {
            // SCENARIO 1: Check if we've found a better (higher) peak than our last one
            bool isNewHigherPeak = (
               HighMapBuffer[shift] != 0.0 &&        // Is a valid high extreme
               HighMapBuffer[shift] > last_high &&   // Is higher than our last one
               LowMapBuffer[shift] == 0.0            // Is not also a low point
            );
            
            if(isNewHigherPeak)
              {
               // Remove the old peak from zigzag line
               ZigzagPeakBuffer[last_high_pos] = 0.0;
               
               // Update our tracking to this better (higher) peak
               last_high_pos = shift;
               last_high = HighMapBuffer[shift];
               
               // Mark new peak point on zigzag line
               ZigzagPeakBuffer[shift] = last_high;
               ColorBuffer[shift] = TREND_UP;
              }
            
            // SCENARIO 2: Check if we've found a bottom to connect to
            bool isValidBottom = (
               LowMapBuffer[shift] != 0.0 &&         // Is a valid low extreme
               HighMapBuffer[shift] == 0.0           // Is not also a high point
            );
            
            if(isValidBottom)
              {
               // Record this bottom
               last_low = LowMapBuffer[shift];
               last_low_pos = shift;
               
               // Mark this point on zigzag line
               ZigzagBottomBuffer[shift] = last_low;
               ColorBuffer[shift] = TREND_DOWN;
               
               // Now switch to looking for the next peak
               extreme_search = SEARCH_NEXT_PEAK;
              }
            break;
           }
         
         default:
            return;  // Safety exit for invalid state
        }
     }
}

//+------------------------------------------------------------------+
//| Search for high and low extremes in the price data               |
//+------------------------------------------------------------------+
void FindExtremes(const int start, 
                 const int rates_total, 
                 const double &high[], 
                 const double &low[], 
                 double &last_high, 
                 double &last_low)
{
   //--- searching for high and low extremes by iterating through each price bar
   for(int shift=start; shift<rates_total && !IsStopped(); shift++)
     {
      //--- SECTION 1: FIND LOW EXTREMES (BOTTOMS) ---//
      // Step 1: Find the lowest price within the specified depth
      double lowestValue = Lowest(low, InpDepth, shift);
      
      // Step 2: Check if this lowest value is the same as the previous one we found
      bool isNewLowExtreme = (lowestValue != last_low);
      if(isNewLowExtreme)
        {
         // Update our tracking variable for the last found low
         last_low = lowestValue;
         
         // Step 3: Deviation check - verify the difference between current low and lowest is significant
         bool isDeviationSignificant = ((low[shift] - lowestValue) <= (InpDeviation * _Point));
         
         // Only consider points with significant deviation
         if(!isDeviationSignificant)
           {
            // Not significant enough - cancel this extreme point
            lowestValue = 0.0;
           }
           else
           {
            // Step 4: Look back to check and possibly clear previous extremes
            // This prevents multiple extremes too close together
            for(int back=InpBackstep; back>=1; back--)
              {
               // Get value from previous bars' extreme points
               double previousLowExtreme = LowMapBuffer[shift-back];
               
               // If previous value exists and is higher (worse) than current one, remove it
               if((previousLowExtreme != 0) && (previousLowExtreme > lowestValue))
                  LowMapBuffer[shift-back] = 0.0;
              }
           }
        }
      else
        {
         // Same as previous low extreme - skip it
         lowestValue = 0.0;
        }
      
      // Step 5: Record the low extreme if this bar's low price exactly matches the lowest value
      bool isBarActualLowExtreme = (low[shift] == lowestValue);
      if(isBarActualLowExtreme)
         LowMapBuffer[shift] = lowestValue;  // This is a low extreme point
      else
         LowMapBuffer[shift] = 0.0;  // Not an extreme point
      
      //--- SECTION 2: FIND HIGH EXTREMES (PEAKS) ---//
      // Process is symmetrical to the low extreme search above
      
      // Step 1: Find the highest price within the specified depth
      double highestValue = Highest(high, InpDepth, shift);
      
      // Step 2: Check if this highest value is the same as the previous one we found
      bool isNewHighExtreme = (highestValue != last_high);
      if(isNewHighExtreme)
        {
         // Update our tracking variable for the last found high
         last_high = highestValue;
         
         // Step 3: Deviation check - verify the difference between highest and current high is significant
         bool isDeviationSignificant = ((highestValue - high[shift]) <= (InpDeviation * _Point));
         
         // Only consider points with significant deviation
         if(!isDeviationSignificant)
           {
            // Not significant enough - cancel this extreme point
            highestValue = 0.0;
           }
           else
           {
            // Step 4: Look back to check and possibly clear previous extremes
            // This prevents multiple extremes too close together
            for(int back=InpBackstep; back>=1; back--)
              {
               // Get value from previous bars' extreme points
               double previousHighExtreme = HighMapBuffer[shift-back];
               
               // If previous value exists and is lower (worse) than current one, remove it
               if((previousHighExtreme != 0) && (previousHighExtreme < highestValue))
                  HighMapBuffer[shift-back] = 0.0;
              }
           }
        }
      else
        {
         // Same as previous high extreme - skip it
         highestValue = 0.0;
        }
      
      // Step 5: Record the high extreme if this bar's high price exactly matches the highest value
      bool isBarActualHighExtreme = (high[shift] == highestValue);
      if(isBarActualHighExtreme)
         HighMapBuffer[shift] = highestValue;  // This is a high extreme point
      else
         HighMapBuffer[shift] = 0.0;  // Not an extreme point
     }
}

//+------------------------------------------------------------------+
//| Initialize calculation parameters                                |
//| Returns false if there's an error or insufficient data           |
//+------------------------------------------------------------------+
bool InitializeCalculation(const int rates_total,
                         const int prev_calculated,
                         const double &high[],
                         const double &low[],
                         int &start,
                         int &extreme_search,
                         double &cur_high,
                         double &cur_low,
                         double &last_high,
                         double &last_low,
                         int &last_high_pos,
                         int &last_low_pos)
{
   // CASE 1: First calculation or recalculation from scratch
   if(prev_calculated == 0)
     {
      // Clear all indicator buffers to 0.0
      ArrayInitialize(ZigzagPeakBuffer, 0.0);
      ArrayInitialize(ZigzagBottomBuffer, 0.0);
      ArrayInitialize(HighMapBuffer, 0.0);
      ArrayInitialize(LowMapBuffer, 0.0);
      ArrayInitialize(ConfirmPeakBuffer, 0.0);
      ArrayInitialize(ConfirmBottomBuffer, 0.0);
      
      // Start calculation from bar number InpDepth (need enough bars for depth calculation)
      start = InpDepth - 1;
      
      // No need to handle extremes - starting fresh
      return true;
     }
   
   // CASE 2: Continuing calculation - find where to restart from
   if(prev_calculated > 0)
     {
      // We'll search backwards starting from the most recent bar
      int searchStartPosition = rates_total - 1;
      
      // Need to find the third extremum from the end to ensure proper zigzag continuation
      int extremesFound = 0;
      int maxBarsToSearch = 100; // Limit search to recent bars for efficiency
      int searchEndPosition = MathMax(rates_total - maxBarsToSearch, 0);
      
      // Scan backwards looking for existing zigzag points
      int candidatePosition = searchStartPosition;
      while(extremesFound < ExtRecalc && candidatePosition > searchEndPosition)
        {
         // Check if there's a zigzag point at this position
         bool isExtremePoint = (ZigzagPeakBuffer[candidatePosition] != 0 || 
                              ZigzagBottomBuffer[candidatePosition] != 0);
         
         // Count it if found
         if(isExtremePoint)
            extremesFound++;
            
         // Continue searching backward
         candidatePosition--;
        }
      
      // We went one position too far back in the loop
      candidatePosition++;
      
      // This is where we'll restart calculation from
      start = candidatePosition;
      
      // Determine what type of extreme we're looking for next based on the last extreme found
      if(LowMapBuffer[candidatePosition] != 0)
        {
         // Last extreme was a bottom - we're looking for a peak next
         cur_low = LowMapBuffer[candidatePosition];
         extreme_search = SEARCH_NEXT_PEAK;
        }
      else
        {
         // Last extreme was a peak - we're looking for a bottom next
         cur_high = HighMapBuffer[candidatePosition];
         extreme_search = SEARCH_NEXT_BOTTOM;
        }
      
      // Clear all indicator values beyond our starting point to recalculate them
      for(int i = start + 1; i < rates_total && !IsStopped(); i++)
        {
         ZigzagPeakBuffer[i] = 0.0;
         ZigzagBottomBuffer[i] = 0.0;
         LowMapBuffer[i] = 0.0;
         HighMapBuffer[i] = 0.0;
         ConfirmPeakBuffer[i] = 0.0;
         ConfirmBottomBuffer[i] = 0.0;
        }
     }
   
   return true;
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                    |
//| Used to: Only calculate the indicator on new bars when requested |
//| Returns: True if a new bar has formed, False otherwise           |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   // Get the timestamp of the most recent (current) bar
   // In MQL, bar 0 is the current forming bar
   datetime currentBarTimestamp = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Compare with our stored timestamp of the last bar we've seen
   bool isNewBarFormed = (currentBarTimestamp != g_last_bar_time);
   
   // If this is a new bar, update our stored timestamp
   if(isNewBarFormed)
   {
      // Update the global variable to remember this bar's timestamp
      g_last_bar_time = currentBarTimestamp;
      return true;  // Yes, this is a new bar
   }
   
   return false;  // No new bar formed yet
}

//+------------------------------------------------------------------+
//| Get highest value for range                                      |
//| Used to: Find the highest price in a specified range of bars     |
//| Input:  array - price array to search in                         |
//|         count - number of bars to look back                      |
//|         start - starting position for the search                 |
//| Returns: The highest price value found                           |
//+------------------------------------------------------------------+
double Highest(const double&array[], int count, int start)
{
   // Start with the price at the starting position
   double highestValue = array[start];
   
   // Look back 'count' bars from the starting position
   // This loop searches from newer bars to older bars (backwards)
   int oldestBar = MathMax(start - count + 1, 0);  // Ensure we don't go beyond array bounds
   
   // Search each bar in the range for a higher value
   for(int barIndex = start - 1; barIndex >= oldestBar; barIndex--)
   {
      // If we found a higher value, update our highest value
      if(array[barIndex] > highestValue)
         highestValue = array[barIndex];
   }
   
   return highestValue;
}

//+------------------------------------------------------------------+
//| Get lowest value for range                                       |
//| Used to: Find the lowest price in a specified range of bars      |
//| Input:  array - price array to search in                         |
//|         count - number of bars to look back                      |
//|         start - starting position for the search                 |
//| Returns: The lowest price value found                            |
//+------------------------------------------------------------------+
double Lowest(const double&array[], int count, int start)
{
   // Start with the price at the starting position
   double lowestValue = array[start];
   
   // Look back 'count' bars from the starting position
   // This loop searches from newer bars to older bars (backwards)
   int oldestBar = MathMax(start - count + 1, 0);  // Ensure we don't go beyond array bounds
   
   // Search each bar in the range for a lower value
   for(int barIndex = start - 1; barIndex >= oldestBar; barIndex--)
   {
      // If we found a lower value, update our lowest value
      if(array[barIndex] < lowestValue)
         lowestValue = array[barIndex];
   }
   
   return lowestValue;
}



