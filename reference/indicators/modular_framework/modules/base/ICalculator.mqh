//+------------------------------------------------------------------+
//| ICalculator.mqh                                                  |
//| Calculator Module Interface                                      |
//| Defines interface for all calculation modules                    |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property version   "1.00"

#include "IModule.mqh"

//+------------------------------------------------------------------+
//| Applied Price Types                                              |
//+------------------------------------------------------------------+
enum ENUM_APPLIED_PRICE_EX
{
    PRICE_CLOSE_EX = 0,     // Close price
    PRICE_OPEN_EX = 1,      // Open price  
    PRICE_HIGH_EX = 2,      // High price
    PRICE_LOW_EX = 3,       // Low price
    PRICE_MEDIAN_EX = 4,    // Median price (High+Low)/2
    PRICE_TYPICAL_EX = 5,   // Typical price (High+Low+Close)/3
    PRICE_WEIGHTED_EX = 6,  // Weighted price (High+Low+Close+Close)/4
    PRICE_HL2_EX = 7,       // (High+Low)/2
    PRICE_HLC3_EX = 8,      // (High+Low+Close)/3
    PRICE_HLCC4_EX = 9      // (High+Low+Close+Close)/4
};

//+------------------------------------------------------------------+
//| Calculator Parameters Structure                                  |
//+------------------------------------------------------------------+
struct SCalculatorParams
{
    int               period;           // Calculation period
    ENUM_APPLIED_PRICE_EX applied_price; // Applied price
    int               shift;            // Shift value
    double            multiplier;       // Multiplier for calculations
    double            deviation;        // Deviation value
    bool              use_previous_calculated; // Use previous calculated values
    string            symbol;           // Symbol for calculation
    ENUM_TIMEFRAMES   timeframe;        // Timeframe for calculation
};

//+------------------------------------------------------------------+
//| Calculator Interface                                             |
//+------------------------------------------------------------------+
class ICalculator : public IModule
{
protected:
    SCalculatorParams m_params;         // Calculator parameters
    double            m_buffer[];       // Main calculation buffer
    double            m_temp_buffer[];  // Temporary calculation buffer
    int               m_buffer_size;    // Buffer size
    bool              m_buffer_initialized; // Buffer initialization status

public:
    //--- Constructor/Destructor
                      ICalculator(string name = "Calculator") : IModule(name), m_buffer_size(0), m_buffer_initialized(false) {}
    virtual          ~ICalculator() {}
    
    //--- Pure virtual calculation methods
    virtual double    Calculate(const double &high[], const double &low[], 
                               const double &open[], const double &close[], 
                               const long &tick_volume[], const long &volume[], 
                               const datetime &time[], int begin, int index) = 0;
    
    virtual bool      CalculateBuffer(const double &high[], const double &low[], 
                                     const double &open[], const double &close[], 
                                     const long &tick_volume[], const long &volume[], 
                                     const datetime &time[], int rates_total, 
                                     int prev_calculated, int begin, double &buffer[]) = 0;
    
    //--- Parameter management
    virtual bool      SetParameters(const SCalculatorParams &params);
    virtual SCalculatorParams GetParameters() const { return m_params; }
    
    //--- Buffer management
    virtual bool      InitializeBuffers(int size);
    virtual bool      ResizeBuffers(int new_size);
    virtual void      ClearBuffers();
    virtual int       GetBufferSize() const { return m_buffer_size; }
    virtual bool      IsBufferInitialized() const { return m_buffer_initialized; }
    
    //--- Data access
    virtual double    GetValue(int index) const;
    virtual bool      SetValue(int index, double value);
    virtual double*   GetBuffer() { return m_buffer; }
    
    //--- Utility methods
    virtual double    GetPrice(const double &high[], const double &low[], 
                              const double &open[], const double &close[], 
                              ENUM_APPLIED_PRICE_EX price_type, int index);
};

//+------------------------------------------------------------------+
//| Set calculator parameters                                        |
//+------------------------------------------------------------------+
bool ICalculator::SetParameters(const SCalculatorParams &params)
{
    if(params.period <= 0)
    {
        SetError("Invalid period parameter");
        return false;
    }
    
    m_params = params;
    
    // Set default values if not specified
    if(m_params.symbol == "")
        m_params.symbol = Symbol();
    if(m_params.timeframe == PERIOD_CURRENT)
        m_params.timeframe = Period();
    
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Initialize calculation buffers                                   |
//+------------------------------------------------------------------+
bool ICalculator::InitializeBuffers(int size)
{
    if(size <= 0)
    {
        SetError("Invalid buffer size");
        return false;
    }
    
    m_buffer_size = size;
    
    if(ArrayResize(m_buffer, size) < 0)
    {
        SetError("Failed to resize main buffer");
        return false;
    }
    
    if(ArrayResize(m_temp_buffer, size) < 0)
    {
        SetError("Failed to resize temporary buffer");
        return false;
    }
    
    ArrayInitialize(m_buffer, EMPTY_VALUE);
    ArrayInitialize(m_temp_buffer, EMPTY_VALUE);
    
    m_buffer_initialized = true;
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Resize calculation buffers                                       |
//+------------------------------------------------------------------+
bool ICalculator::ResizeBuffers(int new_size)
{
    if(new_size <= 0)
    {
        SetError("Invalid new buffer size");
        return false;
    }
    
    if(ArrayResize(m_buffer, new_size) < 0)
    {
        SetError("Failed to resize main buffer");
        return false;
    }
    
    if(ArrayResize(m_temp_buffer, new_size) < 0)
    {
        SetError("Failed to resize temporary buffer");
        return false;
    }
    
    m_buffer_size = new_size;
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Clear calculation buffers                                        |
//+------------------------------------------------------------------+
void ICalculator::ClearBuffers()
{
    if(m_buffer_initialized)
    {
        ArrayInitialize(m_buffer, EMPTY_VALUE);
        ArrayInitialize(m_temp_buffer, EMPTY_VALUE);
    }
}

//+------------------------------------------------------------------+
//| Get value from buffer                                            |
//+------------------------------------------------------------------+
double ICalculator::GetValue(int index) const
{
    if(!m_buffer_initialized || index < 0 || index >= m_buffer_size)
        return EMPTY_VALUE;
    
    return m_buffer[index];
}

//+------------------------------------------------------------------+
//| Set value in buffer                                              |
//+------------------------------------------------------------------+
bool ICalculator::SetValue(int index, double value)
{
    if(!m_buffer_initialized || index < 0 || index >= m_buffer_size)
        return false;
    
    m_buffer[index] = value;
    return true;
}

//+------------------------------------------------------------------+
//| Get price based on applied price type                           |
//+------------------------------------------------------------------+
double ICalculator::GetPrice(const double &high[], const double &low[], 
                            const double &open[], const double &close[], 
                            ENUM_APPLIED_PRICE_EX price_type, int index)
{
    switch(price_type)
    {
        case PRICE_CLOSE_EX:    return close[index];
        case PRICE_OPEN_EX:     return open[index];
        case PRICE_HIGH_EX:     return high[index];
        case PRICE_LOW_EX:      return low[index];
        case PRICE_MEDIAN_EX:   return (high[index] + low[index]) / 2.0;
        case PRICE_TYPICAL_EX:  return (high[index] + low[index] + close[index]) / 3.0;
        case PRICE_WEIGHTED_EX: return (high[index] + low[index] + close[index] + close[index]) / 4.0;
        case PRICE_HL2_EX:      return (high[index] + low[index]) / 2.0;
        case PRICE_HLC3_EX:     return (high[index] + low[index] + close[index]) / 3.0;
        case PRICE_HLCC4_EX:    return (high[index] + low[index] + close[index] + close[index]) / 4.0;
        default:                return close[index];
    }
} 