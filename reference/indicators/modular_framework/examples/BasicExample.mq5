//+------------------------------------------------------------------+
//| BasicExample.mq5                                                |
//| Basic Modular Framework Example                                 |
//| Simplest possible usage of the framework                       |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- plot Basic Line
#property indicator_label1  "Basic"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Include only what we need
#include "../modules/base/IModule.mqh"
#include "../modules/calculators/MACalculator.mqh"

//--- Simple input parameters
input int Period = 10;          // Calculation Period
input color LineColor = clrGreen; // Line Color

//--- Global variables
CMACalculator* g_calculator;    // Calculator module
double Buffer[];                // Data buffer

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== Basic Modular Example Starting ===");
    
    // Create calculator
    g_calculator = new CMACalculator();
    if(g_calculator == NULL)
    {
        Print("ERROR: Failed to create calculator");
        return INIT_FAILED;
    }
    
    // Setup simple parameters
    SMACalculatorParams params;
    params.base.period = Period;
    params.base.applied_price = PRICE_CLOSE_EX;
    params.ma_method = MODE_SMA_EX;
    
    if(!g_calculator.SetMAParameters(params))
    {
        Print("ERROR: Failed to set parameters: ", g_calculator.GetLastError());
        delete g_calculator;
        return INIT_FAILED;
    }
    
    // Initialize the calculator
    if(!g_calculator.Initialize())
    {
        Print("ERROR: Failed to initialize calculator: ", g_calculator.GetLastError());
        delete g_calculator;
        return INIT_FAILED;
    }
    
    // Setup indicator buffer
    SetIndexBuffer(0, Buffer, INDICATOR_DATA);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, LineColor);
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, Period - 1);
    IndicatorSetString(INDICATOR_SHORTNAME, "Basic Example (" + IntegerToString(Period) + ")");
    
    Print("SUCCESS: Basic modular example initialized");
    Print("Module name: ", g_calculator.GetName());
    Print("Module status: ", g_calculator.IsValid() ? "Valid" : "Invalid");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_calculator != NULL)
    {
        g_calculator.Deinitialize();
        delete g_calculator;
        g_calculator = NULL;
    }
    
    Print("Basic modular example deinitialized");
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
    // Basic validation
    if(rates_total < Period)
        return 0;
    
    if(g_calculator == NULL || !g_calculator.IsValid())
    {
        Print("Calculator is not valid");
        return 0;
    }
    
    // Use the modular calculator - this is the key demonstration!
    if(!g_calculator.CalculateBuffer(high, low, open, close, tick_volume, volume, time,
                                    rates_total, prev_calculated, Period - 1, Buffer))
    {
        Print("Calculation failed: ", g_calculator.GetLastError());
        return 0;
    }
    
    // Optional: Show some debug info on first run
    static bool first_run = true;
    if(first_run && rates_total > Period)
    {
        Print("=== Modular Calculation Success ===");
        Print("Rates total: ", rates_total);
        Print("Period: ", Period);
        Print("First calculated value at index ", Period-1, ": ", Buffer[Period-1]);
        Print("Latest value: ", Buffer[rates_total-1]);
        first_run = false;
    }
    
    return rates_total;
}

//+------------------------------------------------------------------+
//| Demonstrate module functionality                                |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(g_calculator != NULL && g_calculator.IsValid())
    {
        // Example of accessing module information
        Comment("Module Status: ", g_calculator.GetName(), " - ", 
                g_calculator.IsInitialized() ? "Ready" : "Not Ready");
    }
}

//+------------------------------------------------------------------+
//| Handle chart events                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if(id == CHARTEVENT_CLICK)
    {
        // Show module info on chart click
        if(g_calculator != NULL)
        {
            string info = "=== Module Information ===" + "\n";
            info += "Name: " + g_calculator.GetName() + "\n";
            info += "Status: " + (g_calculator.IsValid() ? "Valid" : "Invalid") + "\n";
            info += "Initialized: " + (g_calculator.IsInitialized() ? "Yes" : "No") + "\n";
            info += "Buffer Size: " + IntegerToString(g_calculator.GetBufferSize()) + "\n";
            
            Alert(info);
        }
    }
} 