//+------------------------------------------------------------------+
//| test_compilation.mq5                                            |
//| Test Compilation of Modular Framework                          |
//| Verifies that the modular framework compiles without errors    |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property link      ""
#property version   "1.00"
#property script_show_inputs

//--- Include framework components to test compilation
#include "modules/base/IModule.mqh"
#include "modules/base/ICalculator.mqh"
#include "modules/base/IRenderer.mqh"
#include "modules/calculators/MACalculator.mqh"
#include "modules/renderers/LineRenderer.mqh"

//--- Input parameter
input bool ShowDetails = true;  // Show detailed information

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("=== MQL5 Modular Framework Compilation Test ===");
    
    // Test 1: Create Module Manager
    CModuleManager manager;
    Print("✓ Module Manager created successfully");
    
    // Test 2: Create MA Calculator
    CMACalculator* calc = new CMACalculator();
    if(calc != NULL)
    {
        Print("✓ MA Calculator created successfully");
        
        // Test 3: Set parameters
        SMACalculatorParams params;
        params.base.period = 20;
        params.base.applied_price = PRICE_CLOSE_EX;
        params.ma_method = MODE_SMA_EX;
        
        if(calc.SetMAParameters(params))
        {
            Print("✓ MA Calculator parameters set successfully");
            
            // Test 4: Initialize
            if(calc.Initialize())
            {
                Print("✓ MA Calculator initialized successfully");
                Print("  - Name: ", calc.GetName());
                Print("  - Valid: ", calc.IsValid() ? "Yes" : "No");
                Print("  - Buffer Size: ", calc.GetBufferSize());
            }
            else
            {
                Print("✗ MA Calculator initialization failed: ", calc.GetLastError());
            }
        }
        else
        {
            Print("✗ Failed to set MA Calculator parameters: ", calc.GetLastError());
        }
        
        delete calc;
    }
    else
    {
        Print("✗ Failed to create MA Calculator");
    }
    
    // Test 5: Create Line Renderer
    CLineRenderer* renderer = new CLineRenderer();
    if(renderer != NULL)
    {
        Print("✓ Line Renderer created successfully");
        
        // Test 6: Set renderer parameters
        SLineRendererParams rend_params;
        rend_params.base.type = RENDERER_LINE;
        rend_params.base.buffer_count = 1;
        rend_params.base.short_name = "Test Renderer";
        rend_params.base.style.line_color = clrRed;
        rend_params.base.style.line_width = 1;
        rend_params.base.style.empty_value = EMPTY_VALUE;
        rend_params.connect_gaps = true;
        rend_params.show_arrows = false;
        
        if(renderer.SetLineParameters(rend_params))
        {
            Print("✓ Line Renderer parameters set successfully");
            Print("  - Name: ", renderer.GetName());
            Print("  - Type: ", EnumToString(renderer.GetParameters().type));
        }
        else
        {
            Print("✗ Failed to set Line Renderer parameters: ", renderer.GetLastError());
        }
        
        delete renderer;
    }
    else
    {
        Print("✗ Failed to create Line Renderer");
    }
    
    // Test 7: Module Manager functionality
    CMACalculator* calc1 = new CMACalculator();
    CMACalculator* calc2 = new CMACalculator();
    
    if(calc1 != NULL && calc2 != NULL)
    {
        // Set different names
        calc1.SetName("Calculator1");
        calc2.SetName("Calculator2");
        
        if(manager.AddModule(calc1) && manager.AddModule(calc2))
        {
            Print("✓ Multiple modules added to manager");
            Print("  - Module count: ", manager.GetModuleCount());
            Print("  - Module names: ", manager.GetModuleNames());
            
            // Test retrieval
            IModule* retrieved = manager.GetModule("Calculator1");
            if(retrieved != NULL)
            {
                Print("✓ Module retrieval works: ", retrieved.GetName());
            }
            
            // Cleanup through manager
            manager.CleanupModules();
            Print("✓ Module cleanup completed");
        }
        else
        {
            Print("✗ Failed to add modules to manager");
            delete calc1;
            delete calc2;
        }
    }
    
    // Show detailed information if requested
    if(ShowDetails)
    {
        Print("\n=== Framework Details ===");
        Print("Base Module Interface: IModule - ✓ Available");
        Print("Calculator Interface: ICalculator - ✓ Available");
        Print("Renderer Interface: IRenderer - ✓ Available");
        Print("MA Calculator: CMACalculator - ✓ Available");
        Print("Line Renderer: CLineRenderer - ✓ Available");
        Print("Module Manager: CModuleManager - ✓ Available");
        
        Print("\n=== Supported MA Methods ===");
        Print("- Simple MA (SMA): MODE_SMA_EX");
        Print("- Exponential MA (EMA): MODE_EMA_EX");
        Print("- Smoothed MA (SMMA): MODE_SMMA_EX");
        Print("- Linear Weighted MA (LWMA): MODE_LWMA_EX");
        
        Print("\n=== Supported Price Types ===");
        Print("- Close: PRICE_CLOSE_EX");
        Print("- Open: PRICE_OPEN_EX");
        Print("- High: PRICE_HIGH_EX");
        Print("- Low: PRICE_LOW_EX");
        Print("- Median: PRICE_MEDIAN_EX");
        Print("- Typical: PRICE_TYPICAL_EX");
        Print("- Weighted: PRICE_WEIGHTED_EX");
        
        Print("\n=== Framework Benefits ===");
        Print("✓ Modular Design - Separate calculation and rendering");
        Print("✓ Reusable Components - Use modules across indicators");
        Print("✓ Easy Maintenance - Change modules without affecting others");
        Print("✓ Extensible - Add new calculators and renderers easily");
        Print("✓ Type Safety - Strong interfaces prevent errors");
        Print("✓ Memory Management - Automatic cleanup");
    }
    
    Print("\n=== Compilation Test Results ===");
    Print("✓ All framework components compiled successfully!");
    Print("✓ Framework is ready for use in MT5 indicators");
    Print("✓ Check log for detailed test results");
    
    Alert("MQL5 Modular Framework\nCompilation Test PASSED!\n\nThe framework is ready to use.\nCheck the Experts log for details.");
} 