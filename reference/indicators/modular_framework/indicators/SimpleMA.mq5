//+------------------------------------------------------------------+
//| SimpleMA.mq5                                                     |
//| Simple Modularized Moving Average Indicator                     |
//| Demonstrates the modular framework usage                        |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot MA Line
#property indicator_label1  "MA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- plot MA Arrows
#property indicator_label2  "MA Arrows"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrBlue
#property indicator_width2  1

//--- Include modular framework
#include "../modules/base/IModule.mqh"
#include "../modules/calculators/MACalculator.mqh"
#include "../modules/renderers/LineRenderer.mqh"

//--- Input parameters
input int               MA_Period = 14;                // MA Period
input ENUM_MA_METHOD_EX MA_Method = MODE_SMA_EX;       // MA Method
input ENUM_APPLIED_PRICE_EX MA_AppliedPrice = PRICE_CLOSE_EX; // Applied Price
input color             MA_Color = clrRed;             // MA Color
input int               MA_Width = 1;                  // MA Width
input ENUM_LINE_STYLE   MA_Style = STYLE_SOLID;        // MA Style
input bool              Show_Arrows = true;            // Show Direction Arrows
input int               Arrow_Code = 159;              // Arrow Symbol Code
input double            Arrow_Offset = 0.0001;         // Arrow Offset

//--- Global variables
CModuleManager          g_moduleManager;               // Module manager
CMACalculator*          g_maCalculator;                // MA calculator module
CLineRenderer*          g_lineRenderer;                // Line renderer module

//--- Indicator buffers
double                  MABuffer[];                    // MA values buffer
double                  ArrowBuffer[];                 // Arrow buffer

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // Create and configure MA calculator
    g_maCalculator = new CMACalculator();
    if(g_maCalculator == NULL)
    {
        Print("Failed to create MA Calculator");
        return INIT_FAILED;
    }
    
    // Set MA calculator parameters
    SMACalculatorParams ma_params;
    ma_params.base.period = MA_Period;
    ma_params.base.applied_price = MA_AppliedPrice;
    ma_params.base.shift = 0;
    ma_params.base.multiplier = 1.0;
    ma_params.base.deviation = 0.0;
    ma_params.base.use_previous_calculated = true;
    ma_params.base.symbol = Symbol();
    ma_params.base.timeframe = Period();
    ma_params.ma_method = MA_Method;
    ma_params.calculate_on_every_tick = false;
    
    if(!g_maCalculator.SetMAParameters(ma_params))
    {
        Print("Failed to set MA Calculator parameters: ", g_maCalculator.GetLastError());
        return INIT_FAILED;
    }
    
    // Create and configure line renderer
    g_lineRenderer = new CLineRenderer();
    if(g_lineRenderer == NULL)
    {
        Print("Failed to create Line Renderer");
        return INIT_FAILED;
    }
    
    // Set line renderer parameters
    SLineRendererParams line_params;
    line_params.base.type = RENDERER_LINE;
    line_params.base.buffer_count = Show_Arrows ? 2 : 1;
    line_params.base.show_in_data_window = true;
    line_params.base.short_name = "MA(" + IntegerToString(MA_Period) + ")";
    line_params.base.digits = Digits();
    line_params.base.levels_count = 0;
    
    // Style parameters
    line_params.base.style.line_color = MA_Color;
    line_params.base.style.line_width = MA_Width;
    line_params.base.style.line_style = MA_Style;
    line_params.base.style.label = "MA(" + IntegerToString(MA_Period) + ")";
    line_params.base.style.show_data = true;
    line_params.base.style.show_tooltip = true;
    line_params.base.style.draw_begin = MA_Period - 1;
    line_params.base.style.shift = 0;
    line_params.base.style.empty_value = EMPTY_VALUE;
    
    // Line-specific parameters
    line_params.connect_gaps = true;
    line_params.show_arrows = Show_Arrows;
    line_params.arrow_code = Arrow_Code;
    line_params.arrow_offset = Arrow_Offset;
    
    if(!g_lineRenderer.SetLineParameters(line_params))
    {
        Print("Failed to set Line Renderer parameters: ", g_lineRenderer.GetLastError());
        return INIT_FAILED;
    }
    
    // Add modules to manager
    if(!g_moduleManager.AddModule(g_maCalculator))
    {
        Print("Failed to add MA Calculator to module manager");
        return INIT_FAILED;
    }
    
    if(!g_moduleManager.AddModule(g_lineRenderer))
    {
        Print("Failed to add Line Renderer to module manager");
        return INIT_FAILED;
    }
    
    // Initialize all modules
    if(!g_moduleManager.InitializeAll())
    {
        Print("Failed to initialize modules");
        return INIT_FAILED;
    }
    
    // Setup indicator buffers
    SetIndexBuffer(0, MABuffer, INDICATOR_DATA);
    SetIndexBuffer(1, ArrowBuffer, INDICATOR_DATA);
    
    // Configure plot properties
    PlotIndexSetString(0, PLOT_LABEL, "MA(" + IntegerToString(MA_Period) + ")");
    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, MA_Color);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, MA_Width);
    PlotIndexSetInteger(0, PLOT_LINE_STYLE, MA_Style);
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, MA_Period - 1);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    
    if(Show_Arrows)
    {
        PlotIndexSetString(1, PLOT_LABEL, "MA Arrows");
        PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
        PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrBlue);
        PlotIndexSetInteger(1, PLOT_LINE_WIDTH, MA_Width);
        PlotIndexSetInteger(1, PLOT_ARROW, Arrow_Code);
        PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, MA_Period - 1);
        PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    }
    
    // Set indicator properties
    IndicatorSetInteger(INDICATOR_DIGITS, Digits());
    IndicatorSetString(INDICATOR_SHORTNAME, "Modular MA(" + IntegerToString(MA_Period) + ")");
    
    Print("Modular MA initialized successfully with modules: ", g_moduleManager.GetModuleNames());
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Cleanup modules through manager
    g_moduleManager.CleanupModules();
    
    Print("Modular MA deinitialized, reason: ", reason);
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
    // Validate input
    if(rates_total < MA_Period)
        return 0;
    
    // Check if modules are valid
    if(!g_maCalculator.IsValid())
    {
        Print("MA Calculator is not valid: ", g_maCalculator.GetLastError());
        return 0;
    }
    
    if(!g_lineRenderer.IsValid())
    {
        Print("Line Renderer is not valid: ", g_lineRenderer.GetLastError());
        return 0;
    }
    
    // Calculate MA using the calculator module
    if(!g_maCalculator.CalculateBuffer(high, low, open, close, tick_volume, volume, time,
                                      rates_total, prev_calculated, MA_Period - 1, MABuffer))
    {
        Print("Failed to calculate MA buffer: ", g_maCalculator.GetLastError());
        return 0;
    }
    
    // Render using the renderer module
    if(!g_lineRenderer.RenderBuffer(0, MABuffer, rates_total, prev_calculated))
    {
        Print("Failed to render MA buffer: ", g_lineRenderer.GetLastError());
        return 0;
    }
    
    // Handle arrows if enabled
    if(Show_Arrows)
    {
        // Copy line buffer to arrow buffer for processing
        double* line_buffer = g_lineRenderer.GetLineBuffer();
        double* arrow_buffer = g_lineRenderer.GetArrowBuffer();
        
        if(line_buffer != NULL && arrow_buffer != NULL)
        {
            // Copy arrow buffer data to indicator buffer
            int copy_start = (prev_calculated == 0) ? MA_Period - 1 : prev_calculated;
            for(int i = copy_start; i < rates_total; i++)
            {
                if(i < ArraySize(arrow_buffer))
                    ArrowBuffer[i] = arrow_buffer[i];
                else
                    ArrowBuffer[i] = EMPTY_VALUE;
            }
        }
    }
    
    // Return new prev_calculated value
    return rates_total;
}

//+------------------------------------------------------------------+
//| Get MA value for external access                                 |
//+------------------------------------------------------------------+
double GetMAValue(int index)
{
    if(g_maCalculator == NULL || !g_maCalculator.IsValid())
        return EMPTY_VALUE;
    
    if(index < 0 || index >= ArraySize(MABuffer))
        return EMPTY_VALUE;
    
    return MABuffer[index];
}

//+------------------------------------------------------------------+
//| Get MA parameters for external access                           |
//+------------------------------------------------------------------+
string GetMAParameters()
{
    if(g_maCalculator == NULL)
        return "MA Calculator not initialized";
    
    SMACalculatorParams params = g_maCalculator.GetMAParameters();
    string method_name = "";
    
    switch(params.ma_method)
    {
        case MODE_SMA_EX:  method_name = "SMA"; break;
        case MODE_EMA_EX:  method_name = "EMA"; break;
        case MODE_SMMA_EX: method_name = "SMMA"; break;
        case MODE_LWMA_EX: method_name = "LWMA"; break;
        default: method_name = "Unknown"; break;
    }
    
    return StringFormat("%s(%d, %d)", method_name, params.base.period, (int)params.base.applied_price);
}

//+------------------------------------------------------------------+
//| Check if indicator is ready                                      |
//+------------------------------------------------------------------+
bool IsIndicatorReady()
{
    return (g_maCalculator != NULL && g_maCalculator.IsValid() &&
            g_lineRenderer != NULL && g_lineRenderer.IsValid());
} 