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
// CROSS-LANGUAGE PORTING CONSIDERATIONS:
// -------------------------------------
// When porting this indicator to other languages like Python or PineScript:
//
// 1. BUFFER ARRAYS:
//    - MQL uses multiple buffer arrays (HighMapBuffer, LowMapBuffer, ZigzagPeakBuffer, etc.)
//    - Implement these as separate arrays/series in your target language
//
// 2. DATA INDEXING:
//    - In MQL, arrays are indexed with newest bars at index 0
//    - In other platforms (like Python), oldest bars might be first
//    - Adjust array indexing and iteration direction accordingly
//
// 3. STATE MACHINE:
//    - The ZigZag uses a 3-state machine (SEARCH_FIRST_EXTREMUM/NEXT_PEAK/NEXT_BOTTOM)
//    - Maintain these exact states and transition logic
//    - Preserve the alternating pattern of peaks and bottoms
//
// 4. INITIALIZATION:
//    - Handle initial calculation vs. continuation differently
//    - For continuation, find recent extremes to maintain pattern
//
// 5. POINT VALUES:
//    - MQL uses _Point to represent the minimal price change
//    - Replace with the equivalent in your target language
//
// 6. BAR INDEXING:
//    - MQL uses bar indexing where current/newest bar is at index 0
//    - Adjust calculation direction if your platform uses different indexing
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
#property indicator_width2  2                 // Make arrows bigger
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCyan           // Default color for bottom confirmations
#property indicator_width3  2                 // Make arrows bigger
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
input int InpArrowShift=50; // Arrow distance from price in pixels
input color InpUpColor=clrDarkOliveGreen;   // Uptrend color
input color InpDownColor=clrSaddleBrown;    // Downtrend color
input bool InpUpdateOnNewBarOnly=true; // Calculate only on bar completion

// Alert parameters
input bool  InpEnableAlerts = true;      // Enable alerts
input bool  InpEnableSoundAlerts = true; // Enable sound alerts
input bool  InpEnablePushAlerts = false;  // Enable push notifications
input bool  InpEnableEmailAlerts = false; // Enable email alerts
input string InpSoundFile = "alert.wav";  // Sound file name

// Variables to track alerts
datetime last_alert_time = 0;
int last_alert_direction = 0; // 0: none, 1: peak confirmed by bottom, -1: bottom confirmed by peak
bool first_calculation = true;      // Flag to prevent alerts on first load

// Tracking specific zigzag positions for alerts
struct ZigzagExtremeTracker
{
   int peak_pos;            // Position of last confirmed peak
   int bottom_pos;          // Position of last confirmed bottom
   int confirming_peak_pos; // Position of last peak that confirmed a bottom
   int confirming_bottom_pos; // Position of last bottom that confirmed a peak
};

ZigzagExtremeTracker g_extremes = {-1, -1, -1, -1}; // Added 'g_' prefix to avoid conflicts

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

// ZigZag state machine enum - defines what type of extreme point we're looking for
enum EnSearchMode
  {
   /*
    * ZIGZAG STATE MACHINE STATES:
    * These states control the alternating search for peaks and bottoms
    * that forms the zigzag pattern.
    *
    * When porting to other languages:
    * - Maintain these exact numeric values (0, 1, -1)
    * - Preserve the state transition logic:
    *   FIRST → PEAK/BOTTOM → alternating between PEAK and BOTTOM
    */
   SEARCH_FIRST_EXTREMUM = 0,  // Initial state: searching for the first extremum (peak or bottom)
   SEARCH_NEXT_PEAK = 1,       // Looking for the next peak (after finding a bottom)
   SEARCH_NEXT_BOTTOM = -1     // Looking for the next bottom (after finding a peak)
  };

// Constants for clarity when porting to other languages
#define TREND_UP 0    // Index for uptrend color - needed for ColorBuffer assignments
#define TREND_DOWN 1  // Index for downtrend color - needed for ColorBuffer assignments

// Debug function - can be useful for troubleshooting
void DebugPrint(string message)
{
   // Uncomment to enable debug printing
   // Print(message);
}

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
   PlotIndexSetInteger(1,PLOT_ARROW,234); // Down arrow for peak confirmations
   PlotIndexSetInteger(2,PLOT_ARROW,233); // Up arrow for bottom confirmations
   //--- set arrow vertical shift in pixels
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,-InpArrowShift); // Peak confirmations shifted UP (away from price)
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,InpArrowShift); // Bottom confirmations shifted DOWN (away from price)
   
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
      PlotIndexSetInteger(1,PLOT_ARROW,234); // Down arrow for peak confirmations
      PlotIndexSetInteger(2,PLOT_ARROW,233); // Up arrow for bottom confirmations
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
   /*
    * ZIGZAG CALCULATION FLOW:
    * -----------------------
    * This function implements the main ZigZag calculation algorithm:
    * 1. Skip calculation if requested (on non-new bars)
    * 2. Initialize calculation variables based on previous state
    * 3. Find high/low extreme points in the price data
    * 4. Select and connect extremes to form the zigzag pattern
    * 5. Apply visual features (non-repainting, confirmation markers)
    * 
    * When porting to another language, maintain this sequence of steps.
    * Pay special attention to the state machine (extreme_search) that
    * alternates between finding peaks and bottoms.
    */
    
   // STEP 1: Check early exit conditions
   
   // Check if we should only update on new bars
   if(InpUpdateOnNewBarOnly && prev_calculated > 0)
   {
      // If user has selected to update only on bar completion and this is not a new bar
      if(!IsNewBar())
         return(prev_calculated); // Skip calculation on this tick
   }

   // Check if this is the first calculation after loading
   bool is_first_run = (prev_calculated <= 0);
     
   // Ensure we have enough data for calculation
   if(rates_total < 100)
      return(0);

   // STEP 2: Initialize calculation variables
   
   // Declare variables for tracking extreme points and search state
   int start = 0;                        // Bar index where calculation starts
   int extreme_search = SEARCH_FIRST_EXTREMUM; // Current state in the zigzag state machine
   double current_high = 0.0;            // Potential new high value being evaluated
   double current_low = 0.0;             // Potential new low value being evaluated
   double last_high = 0.0;               // Most recent confirmed high extreme
   double last_low = 0.0;                // Most recent confirmed low extreme
   int last_high_pos = 0;                // Bar index of the most recent high extreme
   int last_low_pos = 0;                 // Bar index of the most recent low extreme
   
   // Set up initial conditions based on previous calculation state
   bool initSuccess = InitializeCalculation(
      rates_total, 
      prev_calculated, 
      high, 
      low, 
      start, 
      extreme_search, 
      current_high, 
      current_low, 
      last_high, 
      last_low, 
      last_high_pos, 
      last_low_pos
   );
   
   // Exit if initialization failed
   if(!initSuccess)
      return rates_total;

   // STEP 3: Find high and low extremes in the price data
   FindExtremes(start, rates_total, high, low, last_high, last_low);

   // STEP 4: Set values for continuation in next calculation
   if(extreme_search == SEARCH_FIRST_EXTREMUM) // No extremes found yet
     {
      last_low = 0.0;
      last_high = 0.0;
     }
   else // Update with current values for next calculation
     {
      last_low = current_low;
      last_high = current_high;
     }
   
   // STEP 5: Select extreme points to form the ZigZag pattern
   SelectExtremePoints(
      start, 
      rates_total, 
      high, 
      low, 
      extreme_search,
      last_high, 
      last_low, 
      last_high_pos, 
      last_low_pos
   );

   // STEP 6: Handle non-repainting and confirmation visualizations if enabled
   if(InpNoRepaint || InpShowConfirmation)
     {
      HandleNonRepaintingAndConfirmation(rates_total, high, low);
     }

   // Reset first calculation flag after first complete run
   if(first_calculation && prev_calculated > 0)
   {
      first_calculation = false;
   }

   // Return value for next calculation
   return rates_total;
  }

//+------------------------------------------------------------------+
//| Handle non-repainting and confirmation display                   |
//+------------------------------------------------------------------+
void HandleNonRepaintingAndConfirmation(const int rates_total,
                                       const double &high[],
                                       const double &low[])
{
    // Define a struct to store extreme point information
    struct ZigzagExtremePoint 
    {
       int position;     // Bar position (index) in the data arrays
       bool isPeak;      // True if this is a peak, false if it's a bottom
       double value;     // Price value of this extreme point
    };
    
    // Find the last three extremes (need three to confirm the middle one)
    int requiredExtremesCount = 3;  // We need to find this many recent extremes
    ZigzagExtremePoint extremes[3]; // Array to store the last three extremes
    
    // Initialize extreme points array
    for(int i=0; i<requiredExtremesCount; i++) {
       extremes[i].position = -1; // -1 means not found yet
       extremes[i].isPeak = false;
       extremes[i].value = 0.0;
    }
    
    // STEP 1: Find positions of the last extremes by scanning backward from the most recent bar
    int extremeCount = 0;
    // Start from the most recent bar (rates_total-1) and scan backward
    for(int barIndex=rates_total-1; barIndex>=0 && extremeCount < requiredExtremesCount; barIndex--)
     {
       // Check if this bar has either a peak or bottom extreme point
       bool hasPeakExtreme = (ZigzagPeakBuffer[barIndex] != 0);
       bool hasBottomExtreme = (ZigzagBottomBuffer[barIndex] != 0);
       bool isExtremePoint = (hasPeakExtreme || hasBottomExtreme);
       
       if(isExtremePoint)
         {
          // Record this extreme point's details
          extremes[extremeCount].position = barIndex;
          extremes[extremeCount].isPeak = hasPeakExtreme;
          extremes[extremeCount].value = hasPeakExtreme ? 
                                        ZigzagPeakBuffer[barIndex] : 
                                        ZigzagBottomBuffer[barIndex];
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
       // Extract positions and types to pass to the function
       int positions[3];
       bool isPeaks[3];
       
       for(int i=0; i<extremeCount; i++) {
          positions[i] = extremes[i].position;
          isPeaks[i] = extremes[i].isPeak;
       }
       
       // Pass arrays directly rather than struct array
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
   ArrayInitialize(ConfirmPeakBuffer, 0.0);
   ArrayInitialize(ConfirmBottomBuffer, 0.0);
   
   bool found_peak_confirmation = false;
   bool found_bottom_confirmation = false;
   int new_peak_confirmation_pos = -1;
   int new_bottom_confirmation_pos = -1;
   int confirming_extreme_pos = -1;
   
   // STEP 1: First scan through bars to identify zigzag extremes and mark confirmations
   // We'll build two separate lists: peaks and bottoms with their confirmations
   
   // Arrays to store extreme points and their confirmation positions - use dynamic arrays
   int peak_positions[], bottom_positions[];
   int peak_confirmation_positions[], bottom_confirmation_positions[];
   
   // Initialize arrays with enough capacity
   ArrayResize(peak_positions, rates_total);
   ArrayResize(bottom_positions, rates_total);
   ArrayResize(peak_confirmation_positions, rates_total);
   ArrayResize(bottom_confirmation_positions, rates_total);
   
   int peak_count = 0, bottom_count = 0;
   
   // First identify all peaks and bottoms
   for(int i = 0; i < rates_total; i++)
   {
      if(ZigzagPeakBuffer[i] != 0)
      {
         peak_positions[peak_count++] = i;
      }
      else if(ZigzagBottomBuffer[i] != 0)
      {
         bottom_positions[bottom_count++] = i;
      }
   }
   
   // Resize arrays to actual count for efficiency
   ArrayResize(peak_positions, peak_count);
   ArrayResize(bottom_positions, bottom_count);
   ArrayResize(peak_confirmation_positions, peak_count);
   ArrayResize(bottom_confirmation_positions, bottom_count);
   
   // Safety check
   if(peak_count == 0 || bottom_count == 0)
   {
      DebugPrint("No peaks or bottoms found");
      return; // Nothing to process
   }
   
   // Now find confirming extremes for each peak
   for(int p = 0; p < peak_count; p++)
   {
      peak_confirmation_positions[p] = -1;
      int peak_pos = peak_positions[p];
      
      // Find the first bottom that comes after this peak
      for(int b = 0; b < bottom_count; b++)
      {
         if(bottom_positions[b] > peak_pos)
         {
            peak_confirmation_positions[p] = bottom_positions[b];
            
            // Mark the confirmation on the chart
            ConfirmPeakBuffer[bottom_positions[b]] = high[bottom_positions[b]];
            break;
         }
      }
   }
   
   // Now find confirming extremes for each bottom
   for(int b = 0; b < bottom_count; b++)
   {
      bottom_confirmation_positions[b] = -1;
      int bottom_pos = bottom_positions[b];
      
      // Find the first peak that comes after this bottom
      for(int p = 0; p < peak_count; p++)
      {
         if(peak_positions[p] > bottom_pos)
         {
            bottom_confirmation_positions[b] = peak_positions[p];
            
            // Mark the confirmation on the chart
            ConfirmBottomBuffer[peak_positions[p]] = low[peak_positions[p]];
            break;
         }
      }
   }
   
   // STEP 2: Check for new confirmations that we haven't alerted about yet
   // For peak confirmations
   if(peak_count > 0)
   {
      for(int p = 0; p < peak_count; p++)
      {
         // Only consider peaks that have a confirmation
         if(peak_confirmation_positions[p] >= 0)
         {
            int peak_pos = peak_positions[p];
            int confirmation_pos = peak_confirmation_positions[p];
            
            // Check if this is a new confirmation we haven't alerted about yet
            if(peak_pos > g_extremes.peak_pos && confirmation_pos > g_extremes.confirming_bottom_pos)
            {
               // Only consider extremes near the end of the chart (recent)
               if(rates_total - 1 - confirmation_pos <= 3) // Within last 3 bars
               {
                  DebugPrint(StringFormat("New peak confirmed: Peak at %d confirmed by bottom at %d", 
                           peak_pos, confirmation_pos));
                  
                  found_peak_confirmation = true;
                  new_peak_confirmation_pos = confirmation_pos;
                  confirming_extreme_pos = peak_pos;
                  break;
               }
            }
         }
      }
   }
   
   // For bottom confirmations
   if(bottom_count > 0)
   {
      for(int b = 0; b < bottom_count; b++)
      {
         // Only consider bottoms that have a confirmation
         if(bottom_confirmation_positions[b] >= 0)
         {
            int bottom_pos = bottom_positions[b];
            int confirmation_pos = bottom_confirmation_positions[b];
            
            // Check if this is a new confirmation we haven't alerted about yet
            if(bottom_pos > g_extremes.bottom_pos && confirmation_pos > g_extremes.confirming_peak_pos)
            {
               // Only consider extremes near the end of the chart (recent)
               if(rates_total - 1 - confirmation_pos <= 3) // Within last 3 bars
               {
                  DebugPrint(StringFormat("New bottom confirmed: Bottom at %d confirmed by peak at %d", 
                           bottom_pos, confirmation_pos));
                  
                  found_bottom_confirmation = true;
                  new_bottom_confirmation_pos = confirmation_pos;
                  confirming_extreme_pos = bottom_pos;
                  break;
               }
            }
         }
      }
   }
   
   // STEP 3: ALERTS - Only trigger if this isn't the first calculation and we found new confirmations
   if(InpEnableAlerts && !first_calculation)
   {
      datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
      
      // Check if we should alert for a new peak confirmation
      if(found_peak_confirmation && 
         (last_alert_time != current_time || last_alert_direction != 1))
      {
         string message = StringFormat("ZigZag: %s - %s - Peak confirmed by bottom", 
                                     _Symbol, EnumToString(Period()));
         
         Alert(message);
         
         if(InpEnableSoundAlerts) 
            PlaySound(InpSoundFile);
            
         if(InpEnablePushAlerts) 
            SendNotification(message);
            
         if(InpEnableEmailAlerts) 
            SendMail("ZigZag Alert", message);
         
         // Update tracking variables
         last_alert_time = current_time;
         last_alert_direction = 1;
         g_extremes.peak_pos = confirming_extreme_pos;
         g_extremes.confirming_bottom_pos = new_peak_confirmation_pos;
         
         DebugPrint("Sent peak confirmation alert");
      }
      
      // Check if we should alert for a new bottom confirmation
      if(found_bottom_confirmation && 
         (last_alert_time != current_time || last_alert_direction != -1))
      {
         string message = StringFormat("ZigZag: %s - %s - Bottom confirmed by peak", 
                                     _Symbol, EnumToString(Period()));
         
         Alert(message);
         
         if(InpEnableSoundAlerts) 
            PlaySound(InpSoundFile);
            
         if(InpEnablePushAlerts) 
            SendNotification(message);
            
         if(InpEnableEmailAlerts) 
            SendMail("ZigZag Alert", message);
         
         // Update tracking variables
         last_alert_time = current_time;
         last_alert_direction = -1;
         g_extremes.bottom_pos = confirming_extreme_pos;
         g_extremes.confirming_peak_pos = new_bottom_confirmation_pos;
         
         DebugPrint("Sent bottom confirmation alert");
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
   /*
    * NON-REPAINTING LOGIC OVERVIEW:
    * ------------------------------
    * To prevent repainting in a zigzag indicator, we hide (clear) the most recent
    * zigzag points that haven't been "confirmed" by subsequent price action.
    * 
    * A zigzag extreme point is considered "confirmed" only when the price has
    * reversed enough to create the next extreme point in the opposite direction.
    * 
    * In this implementation:
    * 1. The most recent extreme point is always hidden (cleared)
    * 2. If we don't have at least 3 extremes yet, the second-to-last one is also hidden
    * 
    * When porting to other languages, maintain this clearing logic to ensure
    * only confirmed zigzag points are displayed.
    */
   
   // We need at least one extreme point to apply non-repainting
   if(extremeCount < 1)
      return;
   
   // Extract positions from the arrays for easier access
   int lastExtremePos = positions[0];
   int prevExtremePos = (extremeCount > 1) ? positions[1] : -1;
   int thirdExtremePos = (extremeCount > 2) ? positions[2] : -1;
   
   // STEP 1: Always clear the most recent extreme as it's not confirmed yet
   if(lastExtremePos >= 0)
     {
      // Clear both buffers at this position (only one will have a non-zero value)
      ClearZigzagPoint(lastExtremePos);
      
      // If we have a previous extreme point, clear the zigzag line connecting to it
      if(prevExtremePos >= 0)
        {
         ClearZigzagLine(prevExtremePos, lastExtremePos);
        }
     }
   
   // STEP 2: If we don't have three extremes, the second-to-last one is also not confirmed
   if(thirdExtremePos == -1 && prevExtremePos >= 0)
     {
      // Clear the previous extreme point
      ClearZigzagPoint(prevExtremePos);
      
      // Scan backwards to find the previous extreme before our prevExtremePos
      int priorExtremePos = FindPreviousExtremePosition(prevExtremePos);
      
      // Clear connecting line if we found a prior extreme
      if(priorExtremePos >= 0)
        {
         ClearZigzagLine(priorExtremePos, prevExtremePos);
        }
     }
}

//+------------------------------------------------------------------+
//| Clear a zigzag point at the specified position                   |
//+------------------------------------------------------------------+
void ClearZigzagPoint(const int position)
{
   // Clear both peak and bottom buffers at this position
   ZigzagPeakBuffer[position] = 0;
   ZigzagBottomBuffer[position] = 0;
}

//+------------------------------------------------------------------+
//| Clear zigzag line between two positions (inclusive of end points) |
//+------------------------------------------------------------------+
void ClearZigzagLine(const int startPos, const int endPos)
{
   // Ensure startPos is less than endPos
   int start = MathMin(startPos, endPos);
   int end = MathMax(startPos, endPos);
   
   // Clear all zigzag points between start and end (exclusive of start)
   for(int i=start+1; i<=end; i++)
     {
      ClearZigzagPoint(i);
     }
}

//+------------------------------------------------------------------+
//| Find position of the previous extreme point before the given pos |
//+------------------------------------------------------------------+
int FindPreviousExtremePosition(const int currentPosition)
{
   // Scan backwards to find the previous extreme before the given position
   for(int i=currentPosition-1; i>=0; i--)
     {
      // Check if this position has either a peak or bottom extreme
      bool hasZigzagPoint = (ZigzagPeakBuffer[i] != 0 || ZigzagBottomBuffer[i] != 0);
      
      if(hasZigzagPoint)
         return i;  // Found a previous extreme point
     }
   
   return -1;  // No previous extreme found
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
   /*
    * ZIGZAG STATE MACHINE OVERVIEW:
    * -------------------------------
    * The ZigZag uses a state machine with three states, represented by extreme_search:
    * 1. SEARCH_FIRST_EXTREMUM (0): Looking for the first extreme point (peak or bottom)
    * 2. SEARCH_NEXT_PEAK (1): Looking for a peak after finding a bottom
    * 3. SEARCH_NEXT_BOTTOM (-1): Looking for a bottom after finding a peak
    *
    * Each state follows a specific logic:
    * - In SEARCH_FIRST_EXTREMUM: We identify the first extreme point of any type
    * - In SEARCH_NEXT_PEAK: We either find a peak or a better (lower) bottom
    * - In SEARCH_NEXT_BOTTOM: We either find a bottom or a better (higher) peak
    *
    * When porting to other languages, maintain this state machine logic and the
    * alternating pattern of finding peaks and bottoms.
    */

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
            bool noExtremesFoundYet = (last_low==0 && last_high==0);
            if(noExtremesFoundYet)
              {
               // Check if current bar is a high extreme (peak)
               double highExtreme = HighMapBuffer[shift];
               bool isHighExtreme = (highExtreme != 0);
               
               if(isHighExtreme)
                 {
                  // Record this as our first peak
                  last_high = high[shift];
                  last_high_pos = shift;
                  
                  // Now we'll start looking for a bottom next
                  extreme_search = SEARCH_NEXT_BOTTOM;
                  
                  // Mark this point on the zigzag line
                  ZigzagPeakBuffer[shift] = last_high;
                  ColorBuffer[shift] = TREND_UP;    // Set color for uptrend
                  
                  // Skip checking for a bottom at this same position
                  continue;
                 }
               
               // Check if current bar is a low extreme (bottom)
               double lowExtreme = LowMapBuffer[shift];
               bool isLowExtreme = (lowExtreme != 0);
               
               if(isLowExtreme)
                 {
                  // Record this as our first bottom
                  last_low = low[shift];
                  last_low_pos = shift;
                  
                  // Now we'll start looking for a peak next
                  extreme_search = SEARCH_NEXT_PEAK;
                  
                  // Mark this point on the zigzag line
                  ZigzagBottomBuffer[shift] = last_low;
                  ColorBuffer[shift] = TREND_DOWN;  // Set color for downtrend
                 }
              }
            break;
           }
         
         //--- Case 2: We found a bottom, now looking for next peak or a better bottom
         case SEARCH_NEXT_PEAK:
           {
            // SCENARIO 1: Check if we've found a better (lower) bottom than our last one
            double potentialNewBottom = LowMapBuffer[shift];
            bool isLowExtreme = (potentialNewBottom != 0.0);
            bool isLowerThanLastBottom = (isLowExtreme && potentialNewBottom < last_low);
            bool isNotAlsoHighPoint = (HighMapBuffer[shift] == 0.0);
            
            bool isNewLowerBottom = (isLowExtreme && isLowerThanLastBottom && isNotAlsoHighPoint);
            
            if(isNewLowerBottom)
              {
               // Remove the old bottom from zigzag line
               ZigzagBottomBuffer[last_low_pos] = 0.0;
               
               // Update our tracking to this better (lower) bottom
               last_low_pos = shift;
               last_low = potentialNewBottom;
               
               // Mark new bottom point on zigzag line
               ZigzagBottomBuffer[shift] = last_low;
               ColorBuffer[shift] = TREND_DOWN;  // Set color for downtrend
              }
            
            // SCENARIO 2: Check if we've found a peak to connect to
            double potentialPeak = HighMapBuffer[shift];
            bool isHighExtreme = (potentialPeak != 0.0);
            bool isNotAlsoLowPoint = (LowMapBuffer[shift] == 0.0);
            
            bool isValidPeak = (isHighExtreme && isNotAlsoLowPoint);
            
            if(isValidPeak)
              {
               // Record this peak
               last_high = potentialPeak;
               last_high_pos = shift;
               
               // Mark this point on zigzag line
               ZigzagPeakBuffer[shift] = last_high;
               ColorBuffer[shift] = TREND_UP;  // Set color for uptrend
               
               // Now switch to looking for the next bottom
               extreme_search = SEARCH_NEXT_BOTTOM;
              }
            break;
           }
         
         //--- Case 3: We found a peak, now looking for next bottom or a better peak
         case SEARCH_NEXT_BOTTOM:
           {
            // SCENARIO 1: Check if we've found a better (higher) peak than our last one
            double potentialNewPeak = HighMapBuffer[shift];
            bool isHighExtreme = (potentialNewPeak != 0.0);
            bool isHigherThanLastPeak = (isHighExtreme && potentialNewPeak > last_high);
            bool isNotAlsoLowPoint = (LowMapBuffer[shift] == 0.0);
            
            bool isNewHigherPeak = (isHighExtreme && isHigherThanLastPeak && isNotAlsoLowPoint);
            
            if(isNewHigherPeak)
              {
               // Remove the old peak from zigzag line
               ZigzagPeakBuffer[last_high_pos] = 0.0;
               
               // Update our tracking to this better (higher) peak
               last_high_pos = shift;
               last_high = potentialNewPeak;
               
               // Mark new peak point on zigzag line
               ZigzagPeakBuffer[shift] = last_high;
               ColorBuffer[shift] = TREND_UP;  // Set color for uptrend
              }
            
            // SCENARIO 2: Check if we've found a bottom to connect to
            double potentialBottom = LowMapBuffer[shift];
            bool isLowExtreme = (potentialBottom != 0.0);
            bool isNotAlsoHighPoint = (HighMapBuffer[shift] == 0.0);
            
            bool isValidBottom = (isLowExtreme && isNotAlsoHighPoint);
            
            if(isValidBottom)
              {
               // Record this bottom
               last_low = potentialBottom;
               last_low_pos = shift;
               
               // Mark this point on zigzag line
               ZigzagBottomBuffer[shift] = last_low;
               ColorBuffer[shift] = TREND_DOWN;  // Set color for downtrend
               
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
      double lowestValueInRange = Lowest(low, InpDepth, shift);
      
      // Step 2: Check if this lowest value is the same as the previous one we found
      bool isNewLowExtreme = (lowestValueInRange != last_low);
      
      // If we found a new low extreme value...
      if(isNewLowExtreme)
        {
         // Update our tracking variable for the last found low
         last_low = lowestValueInRange;
         
         // Step 3: Calculate the price difference to check deviation significance
         double priceDifference = low[shift] - lowestValueInRange;
         double minimumRequiredDeviation = InpDeviation * _Point;
         bool isDeviationSignificant = (priceDifference <= minimumRequiredDeviation);
         
         // Only consider points with significant deviation
         if(!isDeviationSignificant)
           {
            // Not significant enough - cancel this extreme point
            lowestValueInRange = 0.0;
           }
           else
           {
            // Step 4: Look back to check and possibly clear previous extremes
            // This prevents multiple extremes too close together
            for(int barsBack=InpBackstep; barsBack>=1; barsBack--)
              {
               int previousBarIndex = shift-barsBack;
               double previousLowExtreme = LowMapBuffer[previousBarIndex];
               
               // If previous value exists and is higher (worse) than current one, remove it
               if((previousLowExtreme != 0) && (previousLowExtreme > lowestValueInRange))
                  LowMapBuffer[previousBarIndex] = 0.0;
              }
           }
        }
      else
        {
         // Same as previous low extreme - skip it
         lowestValueInRange = 0.0;
        }
      
      // Step 5: Record the low extreme if this bar's low price exactly matches the lowest value
      bool isBarActualLowExtreme = (low[shift] == lowestValueInRange);
      
      // Store the extreme point in the buffer or clear it
      if(isBarActualLowExtreme)
         LowMapBuffer[shift] = lowestValueInRange;  // This is a low extreme point
      else
         LowMapBuffer[shift] = 0.0;  // Not an extreme point
      
      //--- SECTION 2: FIND HIGH EXTREMES (PEAKS) ---//
      // Process is symmetrical to the low extreme search above
      
      // Step 1: Find the highest price within the specified depth
      double highestValueInRange = Highest(high, InpDepth, shift);
      
      // Step 2: Check if this highest value is the same as the previous one we found
      bool isNewHighExtreme = (highestValueInRange != last_high);
      
      // If we found a new high extreme value...
      if(isNewHighExtreme)
        {
         // Update our tracking variable for the last found high
         last_high = highestValueInRange;
         
         // Step 3: Calculate the price difference to check deviation significance
         double priceDifference = highestValueInRange - high[shift];
         double minimumRequiredDeviation = InpDeviation * _Point;
         bool isDeviationSignificant = (priceDifference <= minimumRequiredDeviation);
         
         // Only consider points with significant deviation
         if(!isDeviationSignificant)
           {
            // Not significant enough - cancel this extreme point
            highestValueInRange = 0.0;
           }
           else
           {
            // Step 4: Look back to check and possibly clear previous extremes
            // This prevents multiple extremes too close together
            for(int barsBack=InpBackstep; barsBack>=1; barsBack--)
              {
               int previousBarIndex = shift-barsBack;
               double previousHighExtreme = HighMapBuffer[previousBarIndex];
               
               // If previous value exists and is lower (worse) than current one, remove it
               if((previousHighExtreme != 0) && (previousHighExtreme < highestValueInRange))
                  HighMapBuffer[previousBarIndex] = 0.0;
              }
           }
        }
      else
        {
         // Same as previous high extreme - skip it
         highestValueInRange = 0.0;
        }
      
      // Step 5: Record the high extreme if this bar's high price exactly matches the highest value
      bool isBarActualHighExtreme = (high[shift] == highestValueInRange);
      
      // Store the extreme point in the buffer or clear it
      if(isBarActualHighExtreme)
         HighMapBuffer[shift] = highestValueInRange;  // This is a high extreme point
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
   /*
    * CALCULATION INITIALIZATION OVERVIEW:
    * ----------------------------------
    * This function determines where to start/resume calculations based on whether:
    * 1. This is the first calculation (prev_calculated == 0)
    * 2. We're continuing calculation from a previous state
    * 
    * For continuation, we need to find recent zigzag points to properly
    * resume the state machine. This is critical for maintaining the
    * alternating pattern of peaks and bottoms in the zigzag.
    * 
    * When porting to other languages, ensure this initialization logic
    * is properly translated to maintain calculation continuity.
    */
    
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
      
      // Begin in the initial state: searching for first extreme point
      extreme_search = SEARCH_FIRST_EXTREMUM;
      
      // No need to handle extremes - starting fresh
      return true;
     }
   
   // CASE 2: Continuing calculation - find where to restart from
   if(prev_calculated > 0)
     {
      // We need to find the point where we should resume calculation from
      int lastCalculatedBar = rates_total - 1;
      
      // Need to find the third extremum from the end to ensure proper zigzag continuation
      int extremesNeeded = ExtRecalc; // Looking for this many recent extremes
      int extremesFound = 0;
      int maxBarsToSearch = 100; // Limit search to recent bars for efficiency
      int searchStartBar = lastCalculatedBar;
      int searchEndBar = MathMax(lastCalculatedBar - maxBarsToSearch, 0);
      
      // STEP 1: Scan backwards looking for existing zigzag points
      int potentialStartBar = searchStartBar;
      
      // Continue searching while we need more extremes and haven't reached our search limit
      while(extremesFound < extremesNeeded && potentialStartBar > searchEndBar)
        {
         // Check if there's a zigzag point at this position
         bool hasPeakPoint = (ZigzagPeakBuffer[potentialStartBar] != 0);
         bool hasBottomPoint = (ZigzagBottomBuffer[potentialStartBar] != 0);
         bool isExtremePoint = (hasPeakPoint || hasBottomPoint);
         
         // Count it if found
         if(isExtremePoint)
           {
            extremesFound++;
           }
            
         // Continue searching backward
         potentialStartBar--;
        }
      
      // We went one position too far back in the loop
      potentialStartBar++;
      
      // STEP 2: This is where we'll restart calculation from
      start = potentialStartBar;
      
      // STEP 3: Determine what type of extreme we're looking for next based on the last extreme found
      bool isLastExtremeBottom = (LowMapBuffer[potentialStartBar] != 0);
      bool isLastExtremePeak = (HighMapBuffer[potentialStartBar] != 0);
      
      if(isLastExtremeBottom)
        {
         // Last extreme was a bottom - we're looking for a peak next
         cur_low = LowMapBuffer[potentialStartBar];
         extreme_search = SEARCH_NEXT_PEAK;
        }
      else if(isLastExtremePeak)
        {
         // Last extreme was a peak - we're looking for a bottom next
         cur_high = HighMapBuffer[potentialStartBar];
         extreme_search = SEARCH_NEXT_BOTTOM;
        }
      else
        {
         // Fallback - start with initial search state
         extreme_search = SEARCH_FIRST_EXTREMUM;
        }
      
      // STEP 4: Clear all indicator values beyond our starting point to recalculate them
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
double Highest(const double &array[], int count, int start)
{
   /*
    * This function finds the highest value in a range of bars.
    * 
    * Important notes for cross-language porting:
    * - In MQL, arrays are indexed with newest bars at index 0.
    * - Other platforms (like Python) may have oldest bars first.
    * - When porting, ensure the lookback direction is preserved.
    */
    
   // Start with the price at the starting position
   double highestValue = array[start];
   
   // Calculate the oldest bar to check (ensure we don't go beyond array bounds)
   int oldestBarToCheck = MathMax(start - count + 1, 0);
   
   // Search each bar in the range for a higher value (moving from newer to older bars)
   for(int barIndex = start - 1; barIndex >= oldestBarToCheck; barIndex--)
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
double Lowest(const double &array[], int count, int start)
{
   /*
    * This function finds the lowest value in a range of bars.
    * 
    * Important notes for cross-language porting:
    * - In MQL, arrays are indexed with newest bars at index 0.
    * - Other platforms (like Python) may have oldest bars first.
    * - When porting, ensure the lookback direction is preserved.
    */
    
   // Start with the price at the starting position
   double lowestValue = array[start];
   
   // Calculate the oldest bar to check (ensure we don't go beyond array bounds)
   int oldestBarToCheck = MathMax(start - count + 1, 0);
   
   // Search each bar in the range for a lower value (moving from newer to older bars)
   for(int barIndex = start - 1; barIndex >= oldestBarToCheck; barIndex--)
   {
      // If we found a lower value, update our lowest value
      if(array[barIndex] < lowestValue)
         lowestValue = array[barIndex];
   }
   
   return lowestValue;
}



