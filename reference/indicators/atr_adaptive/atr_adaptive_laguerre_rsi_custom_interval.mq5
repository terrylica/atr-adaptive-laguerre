//------------------------------------------------------------------
#property copyright "Eon Labs Ltd. - Custom Interval Version"
#property link      "https://eonlabs.com"
//------------------------------------------------------------------
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   1
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrGray,clrDodgerBlue,clrTomato
#property indicator_width1  2

// Define constants
#define _lagRsiInstances 1

//------------------------------------------------------------------
// Input parameters
//------------------------------------------------------------------
input int                inpCustomMinutes = 0;            // Custom interval in minutes (0 = chart timeframe)
input int                inpHistoryBars   = 5000;         // M1 bars for historical coverage
input int                inpAtrPeriod     = 32;           // ATR period
input ENUM_APPLIED_PRICE inpRsiPrice      = PRICE_CLOSE;  // Price
input int                inpRsiMaPeriod   = 5;            // Price smoothing period
input ENUM_MA_METHOD     inpRsiMaType     = MODE_EMA;     // Price smoothing method
input double             inpLevelUp       = 0.85;         // Level up
input double             inpLevelDown     = 0.15;         // Level down
input bool               inpShowDebug     = false;        // Show debug information

//------------------------------------------------------------------
// Global variables and buffers
//------------------------------------------------------------------
// Indicator buffers
double val[];     // Main indicator values buffer
double valc[];    // Color index buffer
double prices[];  // Price values buffer

// Custom interval data
double customOpen[], customHigh[], customLow[], customClose[];
datetime customTime[];
int customBarCount = 0;

// Forward declarations for structs
struct sLaguerreDataStruct;
struct sLaguerreWorkStruct;

// Global state management
struct sGlobalStruct
{
   int maHandle;  // Handle to moving average indicator
   int maPeriod;  // Effective MA period (enforced minimum)
};
sGlobalStruct global;

//------------------------------------------------------------------
// Data structures
//------------------------------------------------------------------
// Structure to hold True Range and ATR calculation data
struct sAtrWorkStruct
{
   double tr;          // True Range value
   double trSum;       // Sum of TR values for ATR calculation
   double atr;         // ATR value
   double prevMin;     // Minimum ATR in lookback period
   double prevMax;     // Maximum ATR in lookback period
   int    saveBar;     // Bar index for cache management
   
   // Constructor with default initialization
   sAtrWorkStruct() : tr(0.0), trSum(0.0), atr(0.0), prevMin(0.0), prevMax(0.0), saveBar(-1) {};
};

// Structure to hold Laguerre filter values for one instance
struct sLaguerreDataStruct
{
   double values[4];   // Four stages of Laguerre filter
   
   // Constructor with default initialization
   sLaguerreDataStruct()
   {
      ArrayInitialize(values, 0.0);
   }
};

// Structure to hold multiple instances of Laguerre filter data
struct sLaguerreWorkStruct 
{ 
   sLaguerreDataStruct data[_lagRsiInstances]; 
};

// Static work arrays for calculations
static sAtrWorkStruct atrWork[];
static sLaguerreWorkStruct laguerreWork[];

// Function prototypes for compiler
double CalculateTrueRange(const double high, const double low, const double prevClose, bool hasPrevBar);
void CalculateAtrMinMax(const sAtrWorkStruct &atrValues[], int currentBar, int period, double &outMin, double &outMax);
double CalculateAdaptiveCoefficient(double currentAtr, double minAtr, double maxAtr);
double CalculateLaguerreGamma(double period);
void UpdateLaguerreFilter(double price, double gamma, int currentBar, int instance, sLaguerreWorkStruct &work[]);
double CalculateLaguerreRSI(const sLaguerreWorkStruct &work[], int currentBar, int instance);
double iLaGuerreRsi(double price, double period, int i, int bars, int instance=0);

// Custom interval functions
int BuildCustomBars(const MqlRates &m1_rates[], int m1_count);
datetime GetIntervalStart(datetime barTime);
int CalculateNormalTimeframe(int rates_total, int prev_calculated, const datetime &time[], 
                           const double &open[], const double &high[], const double &low[], const double &close[]);
int CalculateCustomTimeframe(int rates_total, int prev_calculated, const datetime &time[]);
void MapResultsToChart(int rates_total, const datetime &chartTime[], const double &customResults[], 
                      const datetime &customTime[], int resultCount);
int CountFilledBars();

//+------------------------------------------------------------------+
//| Indicator initialization function                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   // Setup indicator buffers
   SetupIndicatorBuffers();
   
   // Setup level lines
   SetupLevelLines();
   
   // Initialize price smoothing
   InitializePriceSmoothing();
   
   // Set indicator name with parameters
   string intervalStr = (inpCustomMinutes == 0) ? "Chart TF" : IntegerToString(inpCustomMinutes) + " min";
   string shortName = "ATR adaptive Laguerre RSI (" + intervalStr + ", " +
                     IntegerToString(inpAtrPeriod) + "," + 
                     IntegerToString(inpRsiMaPeriod) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   
   Print("ATR Adaptive Laguerre RSI initialized - Custom Minutes: ", inpCustomMinutes, ", History Bars: ", inpHistoryBars);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Setup indicator buffers and their properties                     |
//+------------------------------------------------------------------+
void SetupIndicatorBuffers()
{
   // Set indicator buffers
   SetIndexBuffer(0, val, INDICATOR_DATA);        // Main values
   SetIndexBuffer(1, valc, INDICATOR_COLOR_INDEX); // Color index
   SetIndexBuffer(2, prices, INDICATOR_CALCULATIONS); // Price data for calculations
   
   // Set arrays as series
   ArraySetAsSeries(val, true);
   ArraySetAsSeries(valc, true);
   ArraySetAsSeries(prices, true);
}

//+------------------------------------------------------------------+
//| Setup indicator level lines                                      |
//+------------------------------------------------------------------+
void SetupLevelLines()
{
   // Set number of level lines
   IndicatorSetInteger(INDICATOR_LEVELS, 2);
   
   // Set level values
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, inpLevelUp);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, inpLevelDown);
}

//+------------------------------------------------------------------+
//| Initialize price smoothing settings                              |
//+------------------------------------------------------------------+
void InitializePriceSmoothing()
{
   // Ensure minimum period value
   global.maPeriod = MathMax(inpRsiMaPeriod, 1);
   
   // Create MA indicator handle for price smoothing
   global.maHandle = iMA(_Symbol, _Period, global.maPeriod, 0, inpRsiMaType, inpRsiPrice);
   
   // Check if handle was created successfully
   if(global.maHandle == INVALID_HANDLE)
   {
      Print("Error creating MA indicator handle");
   }
}

//+------------------------------------------------------------------+
//| Main calculation function called for each bar                     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < inpAtrPeriod) return 0;
   
   // Set arrays as series
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   // If CustomMinutes is 0, use chart timeframe
   if(inpCustomMinutes == 0)
   {
      return CalculateNormalTimeframe(rates_total, prev_calculated, time, open, high, low, close);
   }
   
   // Use custom timeframe
   return CalculateCustomTimeframe(rates_total, prev_calculated, time);
}

//+------------------------------------------------------------------+
//| Calculate using normal chart timeframe                          |
//+------------------------------------------------------------------+
int CalculateNormalTimeframe(int rates_total, int prev_calculated, const datetime &time[], 
                           const double &open[], const double &high[], const double &low[], const double &close[])
{
   // Determine calculation boundaries
   int limit     = (prev_calculated>0) ? prev_calculated-1 : 0;
   int copyCount = (prev_calculated>0) ? rates_total-prev_calculated+1 : rates_total;
   
   // Obtain price data for calculations
   if(CopyBuffer(global.maHandle,0,0,copyCount,prices)!=copyCount)
      return(prev_calculated);

   // Ensure enough memory is allocated for ATR calculations
   static int atrWorkSize = -1;
   if(atrWorkSize <= rates_total)
      atrWorkSize = ArrayResize(atrWork, rates_total+500, 2000);

   // Main calculation loop - iterates through each bar
   for(int i=limit; i<rates_total && !_StopFlag; i++)
   {
      // Replace empty price values with close price
      if(prices[i]==EMPTY_VALUE)
         prices[i]=close[i];

      // Calculate True Range exactly as in original
      atrWork[i].tr = (i>0) ? 
                     (high[i]>close[i-1] ? high[i] : close[i-1]) - 
                     (low[i]<close[i-1] ? low[i] : close[i-1]) 
                     : high[i]-low[i];
      
      // ATR calculation - either using sliding window or initial sum
      if(i>inpAtrPeriod)
      {
         // Sliding window: add newest, remove oldest
         atrWork[i].trSum = atrWork[i-1].trSum + atrWork[i].tr - atrWork[i-inpAtrPeriod].tr;
      }
      else
      {
         // Initial accumulation phase
         atrWork[i].trSum = atrWork[i].tr;
         for(int k=1; k<inpAtrPeriod && i>=k; k++)
            atrWork[i].trSum += atrWork[i-k].tr;
      }
      
      // Calculate ATR as average of TR values
      atrWork[i].atr = atrWork[i].trSum / (double)inpAtrPeriod;

      // Calculate ATR min/max for adaptive coefficient
      if(atrWork[i].saveBar!=i || atrWork[i+1].saveBar>=i)
      {
         // Update cache management indices exactly as original
         atrWork[i  ].saveBar = i;
         atrWork[i+1].saveBar = -1;
         
         if(inpAtrPeriod>1 && i>0)
         {
            // Initialize with previous ATR value exactly as original
            atrWork[i].prevMax = atrWork[i].prevMin = atrWork[i-1].atr;
            
            // Find min/max exactly as original
            for(int k=2; k<inpAtrPeriod && i>=k; k++)
            {
               if(atrWork[i-k].atr > atrWork[i].prevMax)
                  atrWork[i].prevMax = atrWork[i-k].atr;
               if(atrWork[i-k].atr < atrWork[i].prevMin)
                  atrWork[i].prevMin = atrWork[i-k].atr;
            }
         }
         else
         {
            // Not enough data, use current ATR for both min and max
            atrWork[i].prevMax = atrWork[i].prevMin = atrWork[i].atr;
         }
      }

      // Calculate adaptive parameters for Laguerre RSI
      double _max = atrWork[i].prevMax > atrWork[i].atr ? atrWork[i].prevMax : atrWork[i].atr;
      double _min = atrWork[i].prevMin < atrWork[i].atr ? atrWork[i].prevMin : atrWork[i].atr;
      double _coeff = (_min != _max) ? 1.0-(atrWork[i].atr-_min)/(_max-_min) : 0.5;
      
      // Calculate Laguerre RSI with adaptive period exactly as original
      val[i] = iLaGuerreRsi(prices[i], inpAtrPeriod*(_coeff+0.75), i, rates_total);
      
      // Set color based on RSI thresholds
      valc[i] = (val[i]>inpLevelUp) ? 1 : (val[i]<inpLevelDown) ? 2 : 0;
   }

   Comment("Mode: Chart Timeframe\nATR Period: ", inpAtrPeriod, "\nBars calculated: ", rates_total - inpAtrPeriod);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate using custom timeframe                                |
//+------------------------------------------------------------------+
int CalculateCustomTimeframe(int rates_total, int prev_calculated, const datetime &time[])
{
   // Calculate how many M1 bars we need
   int neededM1Bars = MathMax(inpHistoryBars, rates_total * inpCustomMinutes + inpAtrPeriod * inpCustomMinutes);
   
   // Get M1 data - get more bars for better historical coverage
   MqlRates m1_rates[];
   int copied = CopyRates(_Symbol, PERIOD_M1, 0, neededM1Bars, m1_rates);
   
   if(copied <= 0)
   {
      Comment("Error getting M1 data: ", GetLastError());
      return 0;
   }
   
   ArraySetAsSeries(m1_rates, true);
   
   // Build custom bars
   customBarCount = BuildCustomBars(m1_rates, copied);
   
   if(customBarCount < inpAtrPeriod)
   {
      Comment("Not enough custom bars: ", customBarCount, " (need ", inpAtrPeriod, ")");
      return 0;
   }
   
   // Prepare custom prices array for MA calculation
   double customPrices[];
   ArrayResize(customPrices, customBarCount);
   ArraySetAsSeries(customPrices, true);
   
   // Apply price smoothing on custom bars
   for(int i = 0; i < customBarCount; i++)
   {
      double price = 0;
      switch(inpRsiPrice)
      {
         case PRICE_OPEN:   price = customOpen[i]; break;
         case PRICE_HIGH:   price = customHigh[i]; break;
         case PRICE_LOW:    price = customLow[i]; break;
         case PRICE_CLOSE:  price = customClose[i]; break;
         case PRICE_MEDIAN: price = (customHigh[i] + customLow[i]) / 2.0; break;
         case PRICE_TYPICAL: price = (customHigh[i] + customLow[i] + customClose[i]) / 3.0; break;
         case PRICE_WEIGHTED: price = (customHigh[i] + customLow[i] + 2 * customClose[i]) / 4.0; break;
         default: price = customClose[i]; break;
      }
      
      // Apply moving average smoothing
      if(i < global.maPeriod - 1)
      {
         customPrices[i] = price;
      }
      else
      {
         double sum = 0;
         for(int j = 0; j < global.maPeriod; j++)
         {
            double tempPrice = 0;
            switch(inpRsiPrice)
            {
               case PRICE_OPEN:   tempPrice = customOpen[i + j]; break;
               case PRICE_HIGH:   tempPrice = customHigh[i + j]; break;
               case PRICE_LOW:    tempPrice = customLow[i + j]; break;
               case PRICE_CLOSE:  tempPrice = customClose[i + j]; break;
               case PRICE_MEDIAN: tempPrice = (customHigh[i + j] + customLow[i + j]) / 2.0; break;
               case PRICE_TYPICAL: tempPrice = (customHigh[i + j] + customLow[i + j] + customClose[i + j]) / 3.0; break;
               case PRICE_WEIGHTED: tempPrice = (customHigh[i + j] + customLow[i + j] + 2 * customClose[i + j]) / 4.0; break;
               default: tempPrice = customClose[i + j]; break;
            }
            sum += tempPrice;
         }
         customPrices[i] = sum / global.maPeriod;
      }
   }
   
   // Ensure enough memory is allocated for ATR calculations
   static int atrWorkSize = -1;
   if(atrWorkSize <= customBarCount)
      atrWorkSize = ArrayResize(atrWork, customBarCount+500, 2000);

   // Calculate ATR Adaptive Laguerre RSI on custom bars
   double customResults[];
   ArrayResize(customResults, customBarCount);
   ArraySetAsSeries(customResults, true);
   
   // Main calculation loop on custom bars
   for(int i = 0; i < customBarCount && !_StopFlag; i++)
   {
      // Calculate True Range
      atrWork[i].tr = (i > 0) ? 
                     (customHigh[i] > customClose[i-1] ? customHigh[i] : customClose[i-1]) - 
                     (customLow[i] < customClose[i-1] ? customLow[i] : customClose[i-1]) 
                     : customHigh[i] - customLow[i];
      
      // ATR calculation
      if(i > inpAtrPeriod)
      {
         atrWork[i].trSum = atrWork[i-1].trSum + atrWork[i].tr - atrWork[i-inpAtrPeriod].tr;
      }
      else
      {
         atrWork[i].trSum = atrWork[i].tr;
         for(int k = 1; k < inpAtrPeriod && i >= k; k++)
            atrWork[i].trSum += atrWork[i-k].tr;
      }
      
      atrWork[i].atr = atrWork[i].trSum / (double)inpAtrPeriod;

      // Calculate ATR min/max for adaptive coefficient
      if(atrWork[i].saveBar != i || (i < customBarCount - 1 && atrWork[i+1].saveBar >= i))
      {
         atrWork[i].saveBar = i;
         if(i < customBarCount - 1) atrWork[i+1].saveBar = -1;
         
         if(inpAtrPeriod > 1 && i > 0)
         {
            atrWork[i].prevMax = atrWork[i].prevMin = atrWork[i-1].atr;
            
            for(int k = 2; k < inpAtrPeriod && i >= k; k++)
            {
               if(atrWork[i-k].atr > atrWork[i].prevMax)
                  atrWork[i].prevMax = atrWork[i-k].atr;
               if(atrWork[i-k].atr < atrWork[i].prevMin)
                  atrWork[i].prevMin = atrWork[i-k].atr;
            }
         }
         else
         {
            atrWork[i].prevMax = atrWork[i].prevMin = atrWork[i].atr;
         }
      }

      // Calculate adaptive parameters
      double _max = atrWork[i].prevMax > atrWork[i].atr ? atrWork[i].prevMax : atrWork[i].atr;
      double _min = atrWork[i].prevMin < atrWork[i].atr ? atrWork[i].prevMin : atrWork[i].atr;
      double _coeff = (_min != _max) ? 1.0-(atrWork[i].atr-_min)/(_max-_min) : 0.5;
      
      // Calculate Laguerre RSI
      customResults[i] = iLaGuerreRsi(customPrices[i], inpAtrPeriod*(_coeff+0.75), i, customBarCount);
   }
   
   // Map results to chart
   MapResultsToChart(rates_total, time, customResults, customTime, customBarCount);
   
   Comment("Mode: Custom ", inpCustomMinutes, " min\n",
           "M1 bars: ", copied, "\n",
           "Custom bars: ", customBarCount, "\n",
           "ATR Period: ", inpAtrPeriod, "\n",
           "Chart bars filled: ", CountFilledBars());
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Build custom timeframe bars from M1 data                        |
//+------------------------------------------------------------------+
int BuildCustomBars(const MqlRates &m1_rates[], int m1_count)
{
   if(m1_count <= 0) return 0;
   
   int maxCustomBars = m1_count / inpCustomMinutes + 100;
   ArrayResize(customOpen, maxCustomBars);
   ArrayResize(customHigh, maxCustomBars);
   ArrayResize(customLow, maxCustomBars);
   ArrayResize(customClose, maxCustomBars);
   ArrayResize(customTime, maxCustomBars);
   
   ArraySetAsSeries(customOpen, true);
   ArraySetAsSeries(customHigh, true);
   ArraySetAsSeries(customLow, true);
   ArraySetAsSeries(customClose, true);
   ArraySetAsSeries(customTime, true);
   
   int customCount = 0;
   datetime currentIntervalStart = 0;
   double intervalOpen = 0, intervalHigh = 0, intervalLow = 0, intervalClose = 0;
   bool hasData = false;
   
   // Process M1 bars from oldest to newest
   for(int i = m1_count - 1; i >= 0 && customCount < maxCustomBars - 1; i--)
   {
      datetime barTime = m1_rates[i].time;
      datetime intervalStart = GetIntervalStart(barTime);
      
      if(intervalStart != currentIntervalStart)
      {
         // Save completed interval
         if(hasData)
         {
            customOpen[customCount] = intervalOpen;
            customHigh[customCount] = intervalHigh;
            customLow[customCount] = intervalLow;
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
   if(hasData && customCount < maxCustomBars)
   {
      customOpen[customCount] = intervalOpen;
      customHigh[customCount] = intervalHigh;
      customLow[customCount] = intervalLow;
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
   int intervalNum = totalMinutes / inpCustomMinutes;
   int startMinutes = intervalNum * inpCustomMinutes;
   
   datetime dayStart = barTime - (barTime % 86400);
   return dayStart + startMinutes * 60;
}

//+------------------------------------------------------------------+
//| Map custom results to chart bars                                |
//+------------------------------------------------------------------+
void MapResultsToChart(int rates_total, const datetime &chartTime[], const double &customResults[], 
                      const datetime &customTime[], int resultCount)
{
   // Initialize buffers
   for(int i = 0; i < rates_total; i++)
   {
      val[i] = EMPTY_VALUE;
      valc[i] = 0;
   }
   
   // Map values with priority logic
   for(int chartIdx = 0; chartIdx < rates_total; chartIdx++)
   {
      datetime cTime = chartTime[chartIdx];
      int bestIdx = -1;
      
      // First: Find custom bar that contains this time
      for(int customIdx = 0; customIdx < resultCount; customIdx++)
      {
         datetime customStart = customTime[customIdx];
         datetime customEnd = customStart + inpCustomMinutes * 60;
         
         if(cTime >= customStart && cTime < customEnd)
         {
            bestIdx = customIdx;
            break;
         }
      }
      
      // Second: Find closest previous custom bar
      if(bestIdx == -1)
      {
         long minDiff = LONG_MAX;
         for(int customIdx = 0; customIdx < resultCount; customIdx++)
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
         val[chartIdx] = customResults[bestIdx];
         // Set color based on RSI thresholds
         valc[chartIdx] = (val[chartIdx] > inpLevelUp) ? 1 : (val[chartIdx] < inpLevelDown) ? 2 : 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Count how many chart bars have values                           |
//+------------------------------------------------------------------+
int CountFilledBars()
{
   int count = 0;
   int total = ArraySize(val);
   
   for(int i = 0; i < total; i++)
   {
      if(val[i] != EMPTY_VALUE && val[i] != 0)
         count++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Calculate True Range for a single bar                           |
//+------------------------------------------------------------------+
double CalculateTrueRange(const double high, const double low, const double prevClose, bool hasPrevBar)
{
   if(!hasPrevBar) return high - low; // First bar case
   
   // True Range calculation: max(high, prevClose) - min(low, prevClose)
   double highValue = MathMax(high, prevClose);
   double lowValue = MathMin(low, prevClose);
   return highValue - lowValue;
}

//+------------------------------------------------------------------+
//| Main Laguerre RSI function with memory management               |
//+------------------------------------------------------------------+
double iLaGuerreRsi(double price, double period, int i, int bars, int instance=0)
{
   // Ensure enough memory is allocated for all bars
   static int laguerreWorkSize = -1;
   if(laguerreWorkSize < bars)
      laguerreWorkSize = ArrayResize(laguerreWork, bars+500, 2000);

   // Follow exact original logic
   double CU = 0; // Cumulative Up movements
   double CD = 0; // Cumulative Down movements

   if(i > 0 && period > 1)
   {
      // Calculate gamma (filter coefficient) exactly as original
      double _gamma = 1.0 - 10.0/(period+9.0);
      
      // Update filter values exactly as in original
      laguerreWork[i].data[instance].values[0] = price + _gamma * (laguerreWork[i-1].data[instance].values[0] - price);
      laguerreWork[i].data[instance].values[1] = laguerreWork[i-1].data[instance].values[0] + 
                                       _gamma * (laguerreWork[i-1].data[instance].values[1] - laguerreWork[i].data[instance].values[0]);
      laguerreWork[i].data[instance].values[2] = laguerreWork[i-1].data[instance].values[1] + 
                                       _gamma * (laguerreWork[i-1].data[instance].values[2] - laguerreWork[i].data[instance].values[1]);
      laguerreWork[i].data[instance].values[3] = laguerreWork[i-1].data[instance].values[2] + 
                                       _gamma * (laguerreWork[i-1].data[instance].values[3] - laguerreWork[i].data[instance].values[2]);
      
      // Calculate up/down movements exactly as original
      if(laguerreWork[i].data[instance].values[0] >= laguerreWork[i].data[instance].values[1])
         CU = laguerreWork[i].data[instance].values[0] - laguerreWork[i].data[instance].values[1];
      else
         CD = laguerreWork[i].data[instance].values[1] - laguerreWork[i].data[instance].values[0];
         
      if(laguerreWork[i].data[instance].values[1] >= laguerreWork[i].data[instance].values[2])
         CU += laguerreWork[i].data[instance].values[1] - laguerreWork[i].data[instance].values[2];
      else
         CD += laguerreWork[i].data[instance].values[2] - laguerreWork[i].data[instance].values[1];
         
      if(laguerreWork[i].data[instance].values[2] >= laguerreWork[i].data[instance].values[3])
         CU += laguerreWork[i].data[instance].values[2] - laguerreWork[i].data[instance].values[3];
      else
         CD += laguerreWork[i].data[instance].values[3] - laguerreWork[i].data[instance].values[2];
   }
   else
   {
      // Initialize with price exactly as original
      for(int k=0; k<4; k++)
         laguerreWork[i].data[instance].values[k] = price;
   }
   
   // Calculate RSI with exact same formula as original
   return ((CU+CD) != 0) ? CU/(CU+CD) : 0;
}
//+------------------------------------------------------------------+ 