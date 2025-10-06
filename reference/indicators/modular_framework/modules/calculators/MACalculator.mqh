//+------------------------------------------------------------------+
//| MACalculator.mqh                                                 |
//| Moving Average Calculator Module                                 |
//| Implements various moving average calculations                   |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property version   "1.00"

#include "../base/ICalculator.mqh"

//+------------------------------------------------------------------+
//| Moving Average Method Types                                      |
//+------------------------------------------------------------------+
enum ENUM_MA_METHOD_EX
{
    MODE_SMA_EX = 0,    // Simple Moving Average
    MODE_EMA_EX = 1,    // Exponential Moving Average
    MODE_SMMA_EX = 2,   // Smoothed Moving Average
    MODE_LWMA_EX = 3    // Linear Weighted Moving Average
};

//+------------------------------------------------------------------+
//| Moving Average Calculator Parameters                             |
//+------------------------------------------------------------------+
struct SMACalculatorParams
{
    SCalculatorParams base;             // Base calculator parameters
    ENUM_MA_METHOD_EX ma_method;        // MA method
    bool              calculate_on_every_tick; // Calculate on every tick
};

//+------------------------------------------------------------------+
//| Moving Average Calculator Class                                  |
//+------------------------------------------------------------------+
class CMACalculator : public ICalculator
{
private:
    SMACalculatorParams m_ma_params;    // MA-specific parameters
    double              m_ema_factor;   // EMA smoothing factor
    double              m_smma_factor;  // SMMA smoothing factor

public:
    //--- Constructor/Destructor
                        CMACalculator() : ICalculator("MACalculator"), m_ema_factor(0.0), m_smma_factor(0.0) {}
    virtual            ~CMACalculator() {}
    
    //--- IModule interface implementation
    virtual bool        Initialize() override;
    virtual void        Deinitialize() override;
    virtual bool        IsValid() override;
    
    //--- ICalculator interface implementation
    virtual double      Calculate(const double &high[], const double &low[], 
                                 const double &open[], const double &close[], 
                                 const long &tick_volume[], const long &volume[], 
                                 const datetime &time[], int begin, int index) override;
    
    virtual bool        CalculateBuffer(const double &high[], const double &low[], 
                                       const double &open[], const double &close[], 
                                       const long &tick_volume[], const long &volume[], 
                                       const datetime &time[], int rates_total, 
                                       int prev_calculated, int begin, double &buffer[]) override;
    
    //--- MA-specific methods
    bool                SetMAParameters(const SMACalculatorParams &params);
    SMACalculatorParams GetMAParameters() const { return m_ma_params; }
    ENUM_MA_METHOD_EX   GetMAMethod() const { return m_ma_params.ma_method; }
    bool                SetMAMethod(ENUM_MA_METHOD_EX method);
    
    //--- Individual MA calculations
    double              CalculateSMA(const double &price[], int period, int index);
    double              CalculateEMA(const double &price[], int period, int index, double prev_ema = 0.0);
    double              CalculateSMMA(const double &price[], int period, int index, double prev_smma = 0.0);
    double              CalculateLWMA(const double &price[], int period, int index);
    
private:
    //--- Helper methods
    void                CalculateFactors();
    bool                ValidateMAParameters();
    double              GetMAValue(const double &price[], int period, int index, double prev_value = 0.0);
};

//+------------------------------------------------------------------+
//| Initialize MA Calculator                                         |
//+------------------------------------------------------------------+
bool CMACalculator::Initialize()
{
    if(!ValidateMAParameters())
    {
        SetError("Invalid MA parameters");
        return false;
    }
    
    CalculateFactors();
    
    if(!InitializeBuffers(1000)) // Default buffer size
    {
        SetError("Failed to initialize buffers");
        return false;
    }
    
    SetInitialized(true);
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize MA Calculator                                       |
//+------------------------------------------------------------------+
void CMACalculator::Deinitialize()
{
    ClearBuffers();
    SetInitialized(false);
}

//+------------------------------------------------------------------+
//| Check if MA Calculator is valid                                  |
//+------------------------------------------------------------------+
bool CMACalculator::IsValid()
{
    return IsInitialized() && ValidateMAParameters() && IsBufferInitialized();
}

//+------------------------------------------------------------------+
//| Set MA-specific parameters                                       |
//+------------------------------------------------------------------+
bool CMACalculator::SetMAParameters(const SMACalculatorParams &params)
{
    if(!SetParameters(params.base))
        return false;
    
    m_ma_params = params;
    
    if(IsInitialized())
    {
        CalculateFactors();
    }
    
    return ValidateMAParameters();
}

//+------------------------------------------------------------------+
//| Set MA method                                                    |
//+------------------------------------------------------------------+
bool CMACalculator::SetMAMethod(ENUM_MA_METHOD_EX method)
{
    m_ma_params.ma_method = method;
    
    if(IsInitialized())
    {
        CalculateFactors();
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate single MA value                                        |
//+------------------------------------------------------------------+
double CMACalculator::Calculate(const double &high[], const double &low[], 
                               const double &open[], const double &close[], 
                               const long &tick_volume[], const long &volume[], 
                               const datetime &time[], int begin, int index)
{
    if(index < begin || index < m_params.period - 1)
        return EMPTY_VALUE;
    
    // Get price array based on applied price
    double price = GetPrice(high, low, open, close, m_params.applied_price, index);
    
    // For single value calculation, we need to create a temporary price array
    double temp_prices[];
    ArrayResize(temp_prices, m_params.period);
    
    for(int i = 0; i < m_params.period; i++)
    {
        int price_index = index - m_params.period + 1 + i;
        if(price_index >= 0)
            temp_prices[i] = GetPrice(high, low, open, close, m_params.applied_price, price_index);
        else
            temp_prices[i] = price; // Use current price for missing values
    }
    
    return GetMAValue(temp_prices, m_params.period, m_params.period - 1);
}

//+------------------------------------------------------------------+
//| Calculate MA buffer                                              |
//+------------------------------------------------------------------+
bool CMACalculator::CalculateBuffer(const double &high[], const double &low[], 
                                   const double &open[], const double &close[], 
                                   const long &tick_volume[], const long &volume[], 
                                   const datetime &time[], int rates_total, 
                                   int prev_calculated, int begin, double &buffer[])
{
    if(rates_total < m_params.period)
        return false;
    
    // Resize buffer if needed
    if(ArraySize(buffer) < rates_total)
    {
        if(ArrayResize(buffer, rates_total) < 0)
            return false;
    }
    
    // Initialize empty values
    if(prev_calculated == 0)
    {
        for(int i = 0; i < m_params.period - 1; i++)
            buffer[i] = EMPTY_VALUE;
    }
    
    // Calculate starting position
    int start_pos = (prev_calculated == 0) ? m_params.period - 1 : prev_calculated - 1;
    
    // Create price array
    double prices[];
    ArrayResize(prices, rates_total);
    
    for(int i = 0; i < rates_total; i++)
    {
        prices[i] = GetPrice(high, low, open, close, m_params.applied_price, i);
    }
    
    // Calculate MA for each position
    for(int i = start_pos; i < rates_total; i++)
    {
        double prev_value = (i > 0) ? buffer[i - 1] : 0.0;
        buffer[i] = GetMAValue(prices, m_params.period, i, prev_value);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Simple Moving Average                                  |
//+------------------------------------------------------------------+
double CMACalculator::CalculateSMA(const double &price[], int period, int index)
{
    if(index < period - 1)
        return EMPTY_VALUE;
    
    double sum = 0.0;
    for(int i = 0; i < period; i++)
    {
        sum += price[index - i];
    }
    
    return sum / period;
}

//+------------------------------------------------------------------+
//| Calculate Exponential Moving Average                             |
//+------------------------------------------------------------------+
double CMACalculator::CalculateEMA(const double &price[], int period, int index, double prev_ema = 0.0)
{
    if(index < 0)
        return EMPTY_VALUE;
    
    if(index == 0 || prev_ema == 0.0)
    {
        // First value is SMA
        if(index >= period - 1)
            return CalculateSMA(price, period, index);
        else
            return price[index]; // Not enough data, return current price
    }
    
    return (price[index] * m_ema_factor) + (prev_ema * (1.0 - m_ema_factor));
}

//+------------------------------------------------------------------+
//| Calculate Smoothed Moving Average                                |
//+------------------------------------------------------------------+
double CMACalculator::CalculateSMMA(const double &price[], int period, int index, double prev_smma = 0.0)
{
    if(index < 0)
        return EMPTY_VALUE;
    
    if(index == 0 || prev_smma == 0.0)
    {
        // First value is SMA
        if(index >= period - 1)
            return CalculateSMA(price, period, index);
        else
            return price[index]; // Not enough data, return current price
    }
    
    return (prev_smma * (period - 1) + price[index]) / period;
}

//+------------------------------------------------------------------+
//| Calculate Linear Weighted Moving Average                         |
//+------------------------------------------------------------------+
double CMACalculator::CalculateLWMA(const double &price[], int period, int index)
{
    if(index < period - 1)
        return EMPTY_VALUE;
    
    double sum = 0.0;
    double weight_sum = 0.0;
    
    for(int i = 0; i < period; i++)
    {
        int weight = period - i;
        sum += price[index - i] * weight;
        weight_sum += weight;
    }
    
    return sum / weight_sum;
}

//+------------------------------------------------------------------+
//| Calculate factors for EMA and SMMA                              |
//+------------------------------------------------------------------+
void CMACalculator::CalculateFactors()
{
    if(m_params.period > 0)
    {
        m_ema_factor = 2.0 / (m_params.period + 1.0);
        m_smma_factor = 1.0 / m_params.period;
    }
}

//+------------------------------------------------------------------+
//| Validate MA parameters                                           |
//+------------------------------------------------------------------+
bool CMACalculator::ValidateMAParameters()
{
    if(m_params.period <= 0)
        return false;
    
    if(m_ma_params.ma_method < MODE_SMA_EX || m_ma_params.ma_method > MODE_LWMA_EX)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get MA value based on method                                     |
//+------------------------------------------------------------------+
double CMACalculator::GetMAValue(const double &price[], int period, int index, double prev_value = 0.0)
{
    switch(m_ma_params.ma_method)
    {
        case MODE_SMA_EX:  return CalculateSMA(price, period, index);
        case MODE_EMA_EX:  return CalculateEMA(price, period, index, prev_value);
        case MODE_SMMA_EX: return CalculateSMMA(price, period, index, prev_value);
        case MODE_LWMA_EX: return CalculateLWMA(price, period, index);
        default:           return CalculateSMA(price, period, index);
    }
} 