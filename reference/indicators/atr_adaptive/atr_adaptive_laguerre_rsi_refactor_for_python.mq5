//------------------------------------------------------------------
#property copyright "Eon Labs Ltd."
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
input int                inpAtrPeriod   = 32;             // ATR period
input ENUM_APPLIED_PRICE inpRsiPrice    = PRICE_CLOSE;    // Price
input int                inpRsiMaPeriod = 5;              // Price smoothing period
input ENUM_MA_METHOD     inpRsiMaType   = MODE_EMA;       // Price smoothing method
input double             inpLevelUp     = 0.85;           // Level up
input double             inpLevelDown   = 0.15;           // Level down

//------------------------------------------------------------------
// Global variables and buffers
//------------------------------------------------------------------
// Indicator buffers
double val[];     // Main indicator values buffer
double valc[];    // Color index buffer
double prices[];  // Price values buffer

// Forward declarations for structs used in multiple places
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
   string shortName = "ATR adaptive Laguerre RSI (" + 
                     IntegerToString(inpAtrPeriod) + "," + 
                     IntegerToString(inpRsiMaPeriod) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   
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
//| Calculates True Range for a single bar                           |
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
//| Calculates ATR min/max values over period                        |
//+------------------------------------------------------------------+
void CalculateAtrMinMax(const sAtrWorkStruct &atrValues[], int currentBar, int period, double &outMin, double &outMax)
{
   // Initialize with current ATR value
   outMin = outMax = atrValues[currentBar-1].atr;
   
   // Find min/max ATR values over the period
   for(int k=2; k<period && currentBar>=k; k++)
   {
      if(atrValues[currentBar-k].atr > outMax)
         outMax = atrValues[currentBar-k].atr;
      if(atrValues[currentBar-k].atr < outMin)
         outMin = atrValues[currentBar-k].atr;
   }
}

//+------------------------------------------------------------------+
//| Calculates adaptive coefficient based on ATR volatility          |
//+------------------------------------------------------------------+
double CalculateAdaptiveCoefficient(double currentAtr, double minAtr, double maxAtr)
{
   // First, determine the actual min/max comparison like in original
   double _max = maxAtr > currentAtr ? maxAtr : currentAtr;
   double _min = minAtr < currentAtr ? minAtr : currentAtr;
   
   // Calculate normalized position of current ATR in its range
   // using exact same formula as original
   if(_min != _max) // Avoid division by zero
      return 1.0 - (currentAtr - _min) / (_max - _min);
   else
      return 0.5;
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

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate gamma parameter for Laguerre filter                    |
//+------------------------------------------------------------------+
double CalculateLaguerreGamma(double period)
{
   // Convert period to filter coefficient (gamma)
   // Higher period = slower filter (gamma closer to 1.0)
   return 1.0 - 10.0/(period + 9.0);
}

//+------------------------------------------------------------------+
//| Update Laguerre filter values for current bar                    |
//+------------------------------------------------------------------+
void UpdateLaguerreFilter(
   double price,                // Current price value
   double gamma,                // Filter coefficient (0 to 1)
   int currentBar,              // Current bar index
   int instance,                // Instance ID for multiple instances
   sLaguerreWorkStruct &work[]) // Work array storing filter state
{
   // Update the cascade of Laguerre filter values
   // L0 = gamma * L0(prev) + (1-gamma) * price
   // L1 = gamma * L1(prev) + (1-gamma) * L0
   // L2 = gamma * L2(prev) + (1-gamma) * L1
   // L3 = gamma * L3(prev) + (1-gamma) * L2
   
   // First filter stage (price input)
   work[currentBar].data[instance].values[0] = price + gamma * (work[currentBar-1].data[instance].values[0] - price);
   
   // Second filter stage
   work[currentBar].data[instance].values[1] = work[currentBar-1].data[instance].values[0] + 
                                     gamma * (work[currentBar-1].data[instance].values[1] - work[currentBar].data[instance].values[0]);
   
   // Third filter stage
   work[currentBar].data[instance].values[2] = work[currentBar-1].data[instance].values[1] + 
                                     gamma * (work[currentBar-1].data[instance].values[2] - work[currentBar].data[instance].values[1]);
   
   // Fourth filter stage
   work[currentBar].data[instance].values[3] = work[currentBar-1].data[instance].values[2] + 
                                     gamma * (work[currentBar-1].data[instance].values[3] - work[currentBar].data[instance].values[2]);
}

//+------------------------------------------------------------------+
//| Calculate Laguerre RSI from filter values                        |
//+------------------------------------------------------------------+
double CalculateLaguerreRSI(const sLaguerreWorkStruct &work[], int currentBar, int instance)
{
   double cumulativeUp = 0.0;   // Cumulative upward movement
   double cumulativeDown = 0.0; // Cumulative downward movement
   
   // Compare adjacent filter values and accumulate differences
   // as "Up" or "Down" movements
   
   // Compare L0 and L1
   if(work[currentBar].data[instance].values[0] >= work[currentBar].data[instance].values[1])
      cumulativeUp += work[currentBar].data[instance].values[0] - work[currentBar].data[instance].values[1];
   else
      cumulativeDown += work[currentBar].data[instance].values[1] - work[currentBar].data[instance].values[0];
   
   // Compare L1 and L2
   if(work[currentBar].data[instance].values[1] >= work[currentBar].data[instance].values[2])
      cumulativeUp += work[currentBar].data[instance].values[1] - work[currentBar].data[instance].values[2];
   else
      cumulativeDown += work[currentBar].data[instance].values[2] - work[currentBar].data[instance].values[1];
   
   // Compare L2 and L3
   if(work[currentBar].data[instance].values[2] >= work[currentBar].data[instance].values[3])
      cumulativeUp += work[currentBar].data[instance].values[2] - work[currentBar].data[instance].values[3];
   else
      cumulativeDown += work[currentBar].data[instance].values[3] - work[currentBar].data[instance].values[2];
   
   // Calculate RSI value from Up/Down components
   double totalMovement = cumulativeUp + cumulativeDown;
   
   // Avoid division by zero
   if(totalMovement < DBL_EPSILON)
      return 0.5; // Neutral value when no movement
      
   // Return ratio of upward movement to total movement (0.0 to 1.0)
   return cumulativeUp / totalMovement;
}

//+------------------------------------------------------------------+
//| Main Laguerre RSI function with memory management                |
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