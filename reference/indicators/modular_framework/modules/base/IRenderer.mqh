//+------------------------------------------------------------------+
//| IRenderer.mqh                                                    |
//| Renderer Module Interface                                        |
//| Defines interface for all display/rendering modules             |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property version   "1.00"

#include "IModule.mqh"

//+------------------------------------------------------------------+
//| Renderer Types                                                   |
//+------------------------------------------------------------------+
enum ENUM_RENDERER_TYPE
{
    RENDERER_LINE = 0,      // Line renderer
    RENDERER_HISTOGRAM = 1, // Histogram renderer
    RENDERER_ARROW = 2,     // Arrow renderer
    RENDERER_LEVEL = 3,     // Level line renderer
    RENDERER_CHANNEL = 4,   // Channel renderer
    RENDERER_CUSTOM = 5     // Custom renderer
};

//+------------------------------------------------------------------+
//| Renderer Style Parameters                                        |
//+------------------------------------------------------------------+
struct SRendererStyle
{
    color             line_color;       // Line color
    int               line_width;       // Line width
    ENUM_LINE_STYLE   line_style;       // Line style
    string            label;            // Display label
    bool              show_data;        // Show data window values
    bool              show_tooltip;     // Show tooltip
    int               draw_begin;       // Drawing begin index
    int               shift;            // Horizontal shift
    double            empty_value;      // Empty value
};

//+------------------------------------------------------------------+
//| Renderer Parameters Structure                                    |
//+------------------------------------------------------------------+
struct SRendererParams
{
    ENUM_RENDERER_TYPE type;           // Renderer type
    SRendererStyle    style;           // Style parameters
    int               buffer_count;    // Number of buffers
    bool              show_in_data_window; // Show in data window
    string            short_name;      // Short name for display
    int               digits;          // Decimal places
    int               levels_count;    // Number of levels
    double            levels[];        // Level values
    color             levels_color[];  // Level colors
    ENUM_LINE_STYLE   levels_style[];  // Level line styles
    int               levels_width[];  // Level line widths
};

//+------------------------------------------------------------------+
//| Renderer Interface                                               |
//+------------------------------------------------------------------+
class IRenderer : public IModule
{
protected:
    SRendererParams   m_params;         // Renderer parameters
    int               m_buffers_count;  // Number of allocated buffers
    bool              m_buffers_setup;  // Buffers setup status
    int               m_indicator_handle; // Handle for custom indicator calls

public:
    //--- Constructor/Destructor
                      IRenderer(string name = "Renderer") : IModule(name), m_buffers_count(0), m_buffers_setup(false), m_indicator_handle(INVALID_HANDLE) {}
    virtual          ~IRenderer() {}
    
    //--- Pure virtual rendering methods
    virtual bool      SetupBuffers() = 0;
    virtual bool      ConfigureDisplay() = 0;
    virtual bool      UpdateDisplay(const double &buffer[], int start_pos, int count) = 0;
    virtual bool      RenderBuffer(int buffer_index, const double &data[], int rates_total, int prev_calculated) = 0;
    
    //--- Parameter management
    virtual bool      SetParameters(const SRendererParams &params);
    virtual SRendererParams GetParameters() const { return m_params; }
    virtual bool      SetStyle(const SRendererStyle &style);
    virtual SRendererStyle GetStyle() const { return m_params.style; }
    
    //--- Buffer management
    virtual int       GetBuffersCount() const { return m_buffers_count; }
    virtual bool      IsBuffersSetup() const { return m_buffers_setup; }
    virtual bool      AllocateBuffers(int count);
    
    //--- Level management
    virtual bool      SetLevels(const double &levels[], const color &colors[], 
                               const ENUM_LINE_STYLE &styles[], const int &widths[]);
    virtual bool      AddLevel(double level, color clr = clrGray, ENUM_LINE_STYLE style = STYLE_DOT, int width = 1);
    virtual bool      RemoveLevel(double level);
    virtual void      ClearLevels();
    
    //--- Display configuration
    virtual bool      SetIndicatorDigits(int digits);
    virtual bool      SetIndicatorShortName(string name);
    virtual bool      SetDrawBegin(int buffer_index, int begin);
    virtual bool      SetEmptyValue(int buffer_index, double value);
    
    //--- Utility methods
    virtual color     GetBufferColor(int buffer_index) const;
    virtual bool      SetBufferColor(int buffer_index, color clr);
    virtual int       GetBufferWidth(int buffer_index) const;
    virtual bool      SetBufferWidth(int buffer_index, int width);
    virtual ENUM_LINE_STYLE GetBufferStyle(int buffer_index) const;
    virtual bool      SetBufferStyle(int buffer_index, ENUM_LINE_STYLE style);
};

//+------------------------------------------------------------------+
//| Set renderer parameters                                          |
//+------------------------------------------------------------------+
bool IRenderer::SetParameters(const SRendererParams &params)
{
    if(params.buffer_count <= 0)
    {
        SetError("Invalid buffer count");
        return false;
    }
    
    m_params = params;
    
    // Set default style values if not specified
    if(m_params.style.line_color == clrNONE)
        m_params.style.line_color = clrRed;
    if(m_params.style.line_width <= 0)
        m_params.style.line_width = 1;
    if(m_params.style.empty_value == 0.0)
        m_params.style.empty_value = EMPTY_VALUE;
    if(m_params.short_name == "")
        m_params.short_name = GetName();
    
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Set renderer style                                               |
//+------------------------------------------------------------------+
bool IRenderer::SetStyle(const SRendererStyle &style)
{
    m_params.style = style;
    
    // Apply style changes if buffers are already setup
    if(m_buffers_setup)
    {
        return ConfigureDisplay();
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Allocate indicator buffers                                       |
//+------------------------------------------------------------------+
bool IRenderer::AllocateBuffers(int count)
{
    if(count <= 0)
    {
        SetError("Invalid buffer count for allocation");
        return false;
    }
    
    // Use IndicatorBuffers to allocate buffers
    if(!IndicatorBuffers(count))
    {
        SetError("Failed to allocate indicator buffers");
        return false;
    }
    
    m_buffers_count = count;
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Set indicator levels                                             |
//+------------------------------------------------------------------+
bool IRenderer::SetLevels(const double &levels[], const color &colors[], 
                          const ENUM_LINE_STYLE &styles[], const int &widths[])
{
    int count = ArraySize(levels);
    if(count <= 0)
    {
        SetError("No levels provided");
        return false;
    }
    
    // Resize arrays
    ArrayResize(m_params.levels, count);
    ArrayResize(m_params.levels_color, count);
    ArrayResize(m_params.levels_style, count);
    ArrayResize(m_params.levels_width, count);
    
    // Copy values
    ArrayCopy(m_params.levels, levels);
    ArrayCopy(m_params.levels_color, colors);
    ArrayCopy(m_params.levels_style, styles);
    ArrayCopy(m_params.levels_width, widths);
    
    m_params.levels_count = count;
    
    // Set indicator levels
    IndicatorSetInteger(INDICATOR_LEVELS, count);
    for(int i = 0; i < count; i++)
    {
        IndicatorSetDouble(INDICATOR_LEVELVALUE, i, levels[i]);
        IndicatorSetInteger(INDICATOR_LEVELCOLOR, i, colors[i]);
        IndicatorSetInteger(INDICATOR_LEVELSTYLE, i, styles[i]);
        IndicatorSetInteger(INDICATOR_LEVELWIDTH, i, widths[i]);
    }
    
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Add single level                                                 |
//+------------------------------------------------------------------+
bool IRenderer::AddLevel(double level, color clr = clrGray, ENUM_LINE_STYLE style = STYLE_DOT, int width = 1)
{
    int count = m_params.levels_count + 1;
    
    // Resize arrays
    ArrayResize(m_params.levels, count);
    ArrayResize(m_params.levels_color, count);
    ArrayResize(m_params.levels_style, count);
    ArrayResize(m_params.levels_width, count);
    
    // Add new level
    m_params.levels[count - 1] = level;
    m_params.levels_color[count - 1] = clr;
    m_params.levels_style[count - 1] = style;
    m_params.levels_width[count - 1] = width;
    m_params.levels_count = count;
    
    // Update indicator levels
    IndicatorSetInteger(INDICATOR_LEVELS, count);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, count - 1, level);
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, count - 1, clr);
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, count - 1, style);
    IndicatorSetInteger(INDICATOR_LEVELWIDTH, count - 1, width);
    
    return true;
}

//+------------------------------------------------------------------+
//| Remove level                                                     |
//+------------------------------------------------------------------+
bool IRenderer::RemoveLevel(double level)
{
    for(int i = 0; i < m_params.levels_count; i++)
    {
        if(MathAbs(m_params.levels[i] - level) < 0.0001) // Compare with small tolerance
        {
            // Shift remaining levels
            for(int j = i; j < m_params.levels_count - 1; j++)
            {
                m_params.levels[j] = m_params.levels[j + 1];
                m_params.levels_color[j] = m_params.levels_color[j + 1];
                m_params.levels_style[j] = m_params.levels_style[j + 1];
                m_params.levels_width[j] = m_params.levels_width[j + 1];
            }
            
            m_params.levels_count--;
            
            // Resize arrays
            ArrayResize(m_params.levels, m_params.levels_count);
            ArrayResize(m_params.levels_color, m_params.levels_count);
            ArrayResize(m_params.levels_style, m_params.levels_count);
            ArrayResize(m_params.levels_width, m_params.levels_count);
            
            // Update indicator levels
            IndicatorSetInteger(INDICATOR_LEVELS, m_params.levels_count);
            for(int k = 0; k < m_params.levels_count; k++)
            {
                IndicatorSetDouble(INDICATOR_LEVELVALUE, k, m_params.levels[k]);
                IndicatorSetInteger(INDICATOR_LEVELCOLOR, k, m_params.levels_color[k]);
                IndicatorSetInteger(INDICATOR_LEVELSTYLE, k, m_params.levels_style[k]);
                IndicatorSetInteger(INDICATOR_LEVELWIDTH, k, m_params.levels_width[k]);
            }
            
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Clear all levels                                                 |
//+------------------------------------------------------------------+
void IRenderer::ClearLevels()
{
    ArrayFree(m_params.levels);
    ArrayFree(m_params.levels_color);
    ArrayFree(m_params.levels_style);
    ArrayFree(m_params.levels_width);
    m_params.levels_count = 0;
    
    IndicatorSetInteger(INDICATOR_LEVELS, 0);
}

//+------------------------------------------------------------------+
//| Set indicator digits                                             |
//+------------------------------------------------------------------+
bool IRenderer::SetIndicatorDigits(int digits)
{
    if(digits < 0)
        return false;
    
    m_params.digits = digits;
    IndicatorSetInteger(INDICATOR_DIGITS, digits);
    return true;
}

//+------------------------------------------------------------------+
//| Set indicator short name                                         |
//+------------------------------------------------------------------+
bool IRenderer::SetIndicatorShortName(string name)
{
    if(name == "")
        return false;
    
    m_params.short_name = name;
    IndicatorSetString(INDICATOR_SHORTNAME, name);
    return true;
}

//+------------------------------------------------------------------+
//| Set draw begin for buffer                                        |
//+------------------------------------------------------------------+
bool IRenderer::SetDrawBegin(int buffer_index, int begin)
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count || begin < 0)
        return false;
    
    PlotIndexSetInteger(buffer_index, PLOT_DRAW_BEGIN, begin);
    return true;
}

//+------------------------------------------------------------------+
//| Set empty value for buffer                                       |
//+------------------------------------------------------------------+
bool IRenderer::SetEmptyValue(int buffer_index, double value)
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count)
        return false;
    
    PlotIndexSetDouble(buffer_index, PLOT_EMPTY_VALUE, value);
    return true;
}

//+------------------------------------------------------------------+
//| Get buffer color                                                 |
//+------------------------------------------------------------------+
color IRenderer::GetBufferColor(int buffer_index) const
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count)
        return clrNONE;
    
    return (color)PlotIndexGetInteger(buffer_index, PLOT_LINE_COLOR);
}

//+------------------------------------------------------------------+
//| Set buffer color                                                 |
//+------------------------------------------------------------------+
bool IRenderer::SetBufferColor(int buffer_index, color clr)
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count)
        return false;
    
    PlotIndexSetInteger(buffer_index, PLOT_LINE_COLOR, clr);
    return true;
}

//+------------------------------------------------------------------+
//| Get buffer width                                                 |
//+------------------------------------------------------------------+
int IRenderer::GetBufferWidth(int buffer_index) const
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count)
        return 0;
    
    return (int)PlotIndexGetInteger(buffer_index, PLOT_LINE_WIDTH);
}

//+------------------------------------------------------------------+
//| Set buffer width                                                 |
//+------------------------------------------------------------------+
bool IRenderer::SetBufferWidth(int buffer_index, int width)
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count || width <= 0)
        return false;
    
    PlotIndexSetInteger(buffer_index, PLOT_LINE_WIDTH, width);
    return true;
}

//+------------------------------------------------------------------+
//| Get buffer style                                                 |
//+------------------------------------------------------------------+
ENUM_LINE_STYLE IRenderer::GetBufferStyle(int buffer_index) const
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count)
        return STYLE_SOLID;
    
    return (ENUM_LINE_STYLE)PlotIndexGetInteger(buffer_index, PLOT_LINE_STYLE);
}

//+------------------------------------------------------------------+
//| Set buffer style                                                 |
//+------------------------------------------------------------------+
bool IRenderer::SetBufferStyle(int buffer_index, ENUM_LINE_STYLE style)
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count)
        return false;
    
    PlotIndexSetInteger(buffer_index, PLOT_LINE_STYLE, style);
    return true;
} 