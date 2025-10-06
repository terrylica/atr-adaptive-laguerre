//+------------------------------------------------------------------+
//|                                                  ZigzagColor.mq5 |
//|                             Copyright 2000-2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
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

enum EnSearchMode
  {
   Extremum=0, // searching for the first extremum
   Peak=1,     // searching for the next ZigZag peak
   Bottom=-1   // searching for the next ZigZag bottom
  };
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
   int extreme_search=Extremum;
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
   if(extreme_search==0) // undefined values
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
   // Find the last three extremes (need three to confirm the middle one)
   int last_extreme_pos = -1;
   int prev_extreme_pos = -1;
   int third_extreme_pos = -1;
   int extreme_count = 0;
   
   // First pass: find positions of the last three extremes
   for(int i=rates_total-1; i>=0 && extreme_count < 3; i--)
     {
      if(ZigzagPeakBuffer[i] != 0 || ZigzagBottomBuffer[i] != 0)
        {
         if(last_extreme_pos == -1)
            last_extreme_pos = i;
         else if(prev_extreme_pos == -1)
            prev_extreme_pos = i;
         else if(third_extreme_pos == -1)
            third_extreme_pos = i;
         extreme_count++;
        }
     }
   
   // Process zigzag points for confirmation markers if enabled
   if(InpShowConfirmation)
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
         // If we find a peak, look for a subsequent low to confirm it
         if(ZigzagPeakBuffer[i] != 0)
           {
            // Look ahead for a bottom that confirms this peak
            for(int j=i+1; j<rates_total; j++)
              {
               if(ZigzagBottomBuffer[j] != 0)
                 {
                  // Mark confirmation of peak with an up arrow at the reversal point
                  ConfirmPeakBuffer[j] = high[j];
                  break; // Stop after finding the first confirmation
                 }
              }
           }
         // If we find a bottom, look for a subsequent peak to confirm it
         else if(ZigzagBottomBuffer[i] != 0)
           {
            // Look ahead for a peak that confirms this bottom
            for(int j=i+1; j<rates_total; j++)
              {
               if(ZigzagPeakBuffer[j] != 0)
                 {
                  // Mark confirmation of bottom with a down arrow at the reversal point
                  ConfirmBottomBuffer[j] = low[j];
                  break; // Stop after finding the first confirmation
                 }
              }
           }
        }
     }
   
   // If non-repainting is enabled and we have at least two extremes found
   if(InpNoRepaint && last_extreme_pos >= 0 && prev_extreme_pos >= 0)
     {
      // If we don't have a third extreme to confirm the previous one,
      // or if the last extreme is too recent (unconfirmed), remove it to prevent repainting
      
      // Clear the last extreme as it's not yet confirmed by a reversal
      if(ZigzagPeakBuffer[last_extreme_pos] != 0)
        {
         ZigzagPeakBuffer[last_extreme_pos] = 0;
        }
      else if(ZigzagBottomBuffer[last_extreme_pos] != 0)
        {
         ZigzagBottomBuffer[last_extreme_pos] = 0;
        }
      
      // Also clear any zigzag line connecting to the previous extreme
      for(int i=prev_extreme_pos+1; i<last_extreme_pos; i++)
        {
         ZigzagPeakBuffer[i] = 0;
         ZigzagBottomBuffer[i] = 0;
        }
       
      // If we don't have a third extreme to confirm the previous one, 
      // remove the previous extreme too (needs a future extreme to confirm it)
      if(third_extreme_pos == -1)
        {
         if(ZigzagPeakBuffer[prev_extreme_pos] != 0)
           {
            ZigzagPeakBuffer[prev_extreme_pos] = 0;
           }
         else if(ZigzagBottomBuffer[prev_extreme_pos] != 0)
           {
            ZigzagBottomBuffer[prev_extreme_pos] = 0;
           }
         
         // Also clear any zigzag line connecting to the third extreme
         for(int i=0; i<prev_extreme_pos; i++)
           {
            if((ZigzagPeakBuffer[i] != 0 || ZigzagBottomBuffer[i] != 0) && i != third_extreme_pos)
              {
               for(int j=i+1; j<prev_extreme_pos; j++)
                 {
                  ZigzagPeakBuffer[j] = 0;
                  ZigzagBottomBuffer[j] = 0;
                 }
               break;
              }
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
      double res=0.0;
      switch(extreme_search)
        {
         case Extremum:
            if(last_low==0 && last_high==0)
              {
               if(HighMapBuffer[shift]!=0)
                 {
                  last_high=high[shift];
                  last_high_pos=shift;
                  extreme_search=-1;
                  ZigzagPeakBuffer[shift]=last_high;
                  ColorBuffer[shift]=0;
                  res=1;
                 }
               if(LowMapBuffer[shift]!=0)
                 {
                  last_low=low[shift];
                  last_low_pos=shift;
                  extreme_search=1;
                  ZigzagBottomBuffer[shift]=last_low;
                  ColorBuffer[shift]=1;
                  res=1;
                 }
              }
            break;
         case Peak:
            if(LowMapBuffer[shift]!=0.0 && LowMapBuffer[shift]<last_low &&
               HighMapBuffer[shift]==0.0)
              {
               ZigzagBottomBuffer[last_low_pos]=0.0;
               last_low_pos=shift;
               last_low=LowMapBuffer[shift];
               ZigzagBottomBuffer[shift]=last_low;
               ColorBuffer[shift]=1;
               res=1;
              }
            if(HighMapBuffer[shift]!=0.0 && LowMapBuffer[shift]==0.0)
              {
               last_high=HighMapBuffer[shift];
               last_high_pos=shift;
               ZigzagPeakBuffer[shift]=last_high;
               ColorBuffer[shift]=0;
               extreme_search=Bottom;
               res=1;
              }
            break;
         case Bottom:
            if(HighMapBuffer[shift]!=0.0 &&
               HighMapBuffer[shift]>last_high &&
               LowMapBuffer[shift]==0.0)
              {
               ZigzagPeakBuffer[last_high_pos]=0.0;
               last_high_pos=shift;
               last_high=HighMapBuffer[shift];
               ZigzagPeakBuffer[shift]=last_high;
               ColorBuffer[shift]=0;
              }
            if(LowMapBuffer[shift]!=0.0 && HighMapBuffer[shift]==0.0)
              {
               last_low=LowMapBuffer[shift];
               last_low_pos=shift;
               ZigzagBottomBuffer[shift]=last_low;
               ColorBuffer[shift]=1;
               extreme_search=Peak;
              }
            break;
         default:
            return;
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
   //--- searching for high and low extremes
   for(int shift=start; shift<rates_total && !IsStopped(); shift++)
     {
      //--- low
      double val=Lowest(low,InpDepth,shift);
      if(val==last_low)
         val=0.0;
      else
        {
         last_low=val;
         if((low[shift]-val)>(InpDeviation*_Point))
            val=0.0;
         else
           {
            for(int back=InpBackstep; back>=1; back--)
              {
               double res=LowMapBuffer[shift-back];
               //---
               if((res!=0) && (res>val))
                  LowMapBuffer[shift-back]=0.0;
              }
           }
        }
      if(low[shift]==val)
         LowMapBuffer[shift]=val;
      else
         LowMapBuffer[shift]=0.0;
      //--- high
      val=Highest(high,InpDepth,shift);
      if(val==last_high)
         val=0.0;
      else
        {
         last_high=val;
         if((val-high[shift])>(InpDeviation*_Point))
            val=0.0;
         else
           {
            for(int back=InpBackstep; back>=1; back--)
              {
               double res=HighMapBuffer[shift-back];
               //---
               if((res!=0) && (res<val))
                  HighMapBuffer[shift-back]=0.0;
              }
           }
        }
      if(high[shift]==val)
         HighMapBuffer[shift]=val;
      else
         HighMapBuffer[shift]=0.0;
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
   //--- initializing
   if(prev_calculated==0)
     {
      ArrayInitialize(ZigzagPeakBuffer,0.0);
      ArrayInitialize(ZigzagBottomBuffer,0.0);
      ArrayInitialize(HighMapBuffer,0.0);
      ArrayInitialize(LowMapBuffer,0.0);
      ArrayInitialize(ConfirmPeakBuffer,0.0);
      ArrayInitialize(ConfirmBottomBuffer,0.0);
      //--- start calculation from bar number InpDepth
      start=InpDepth-1;
     }
   //--- ZigZag was already calculated before
   if(prev_calculated>0)
     {
      int i=rates_total-1;
      int extreme_counter=0;
      //--- searching for the third extremum from the last uncompleted bar
      while(extreme_counter<ExtRecalc && i>rates_total -100)
        {
         double res=(ZigzagPeakBuffer[i]+ZigzagBottomBuffer[i]);
         //---
         if(res!=0)
            extreme_counter++;
         i--;
        }
      i++;
      start=i;
      //--- what type of exremum we search for
      if(LowMapBuffer[i]!=0)
        {
         cur_low=LowMapBuffer[i];
         extreme_search=Peak;
        }
      else
        {
         cur_high=HighMapBuffer[i];
         extreme_search=Bottom;
        }
      //--- clear indicator values
      for(i=start+1; i<rates_total && !IsStopped(); i++)
        {
         ZigzagPeakBuffer[i]  =0.0;
         ZigzagBottomBuffer[i]=0.0;
         LowMapBuffer[i]      =0.0;
         HighMapBuffer[i]     =0.0;
         ConfirmPeakBuffer[i] =0.0;
         ConfirmBottomBuffer[i]=0.0;
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
   datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_bar_time != g_last_bar_time)
   {
      g_last_bar_time = current_bar_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get highest value for range                                      |
//| Used to: Find the highest price in a specified range of bars     |
//| Input:  array - price array to search in                         |
//|         count - number of bars to look back                      |
//|         start - starting position for the search                 |
//| Returns: The highest price value found                           |
//+------------------------------------------------------------------+
double Highest(const double&array[],int count,int start)
  {
   double res=array[start];
//---
   for(int i=start-1; i>start-count && i>=0; i--)
      if(res<array[i])
         res=array[i];
//---
   return(res);
  }

//+------------------------------------------------------------------+
//| Get lowest value for range                                       |
//| Used to: Find the lowest price in a specified range of bars      |
//| Input:  array - price array to search in                         |
//|         count - number of bars to look back                      |
//|         start - starting position for the search                 |
//| Returns: The lowest price value found                            |
//+------------------------------------------------------------------+
double Lowest(const double&array[],int count,int start)
  {
   double res=array[start];
//---
   for(int i=start-1; i>start-count && i>=0; i--)
      if(res>array[i])
         res=array[i];
//---
   return(res);
  }
