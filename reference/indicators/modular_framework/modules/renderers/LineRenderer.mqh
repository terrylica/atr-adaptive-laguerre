//+------------------------------------------------------------------+
//| LineRenderer.mqh                                                 |
//| Line Renderer Module                                             |
//| Implements line-based display rendering                         |
//+------------------------------------------------------------------+
#property copyright "Modular Framework"
#property version   "1.00"

#include "../base/IRenderer.mqh"

//+------------------------------------------------------------------+
//| Line Renderer Parameters                                         |
//+------------------------------------------------------------------+
struct SLineRendererParams
{
    SRendererParams   base;             // Base renderer parameters
    bool              connect_gaps;     // Connect gaps in data
    bool              show_arrows;      // Show direction arrows
    int               arrow_code;       // Arrow symbol code
    double            arrow_offset;     // Arrow vertical offset
};

//+------------------------------------------------------------------+
//| Line Renderer Class                                              |
//+------------------------------------------------------------------+
class CLineRenderer : public IRenderer
{
private:
    SLineRendererParams m_line_params;  // Line-specific parameters
    double              m_line_buffer[];// Main line buffer
    double              m_arrow_buffer[];// Arrow buffer (if enabled)

public:
    //--- Constructor/Destructor
                        CLineRenderer() : IRenderer("LineRenderer") {}
    virtual            ~CLineRenderer() {}
    
    //--- IModule interface implementation
    virtual bool        Initialize() override;
    virtual void        Deinitialize() override;
    virtual bool        IsValid() override;
    
    //--- IRenderer interface implementation
    virtual bool        SetupBuffers() override;
    virtual bool        ConfigureDisplay() override;
    virtual bool        UpdateDisplay(const double &buffer[], int start_pos, int count) override;
    virtual bool        RenderBuffer(int buffer_index, const double &data[], int rates_total, int prev_calculated) override;
    
    //--- Line-specific methods
    bool                SetLineParameters(const SLineRendererParams &params);
    SLineRendererParams GetLineParameters() const { return m_line_params; }
    bool                SetConnectGaps(bool connect);
    bool                GetConnectGaps() const { return m_line_params.connect_gaps; }
    bool                SetShowArrows(bool show);
    bool                GetShowArrows() const { return m_line_params.show_arrows; }
    bool                SetArrowCode(int code);
    int                 GetArrowCode() const { return m_line_params.arrow_code; }
    
    //--- Buffer access
    double*             GetLineBuffer() { return m_line_buffer; }
    double*             GetArrowBuffer() { return m_arrow_buffer; }
    
private:
    //--- Helper methods
    bool                ValidateLineParameters();
    bool                SetupLineBuffer();
    bool                SetupArrowBuffer();
    void                ProcessGaps(double &buffer[], int start_pos, int count);
    void                UpdateArrows(const double &line_buffer[], double &arrow_buffer[], int start_pos, int count);
};

//+------------------------------------------------------------------+
//| Initialize Line Renderer                                         |
//+------------------------------------------------------------------+
bool CLineRenderer::Initialize()
{
    if(!ValidateLineParameters())
    {
        SetError("Invalid line renderer parameters");
        return false;
    }
    
    if(!SetupBuffers())
    {
        SetError("Failed to setup renderer buffers");
        return false;
    }
    
    if(!ConfigureDisplay())
    {
        SetError("Failed to configure display");
        return false;
    }
    
    SetInitialized(true);
    ResetError();
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Line Renderer                                       |
//+------------------------------------------------------------------+
void CLineRenderer::Deinitialize()
{
    ArrayFree(m_line_buffer);
    ArrayFree(m_arrow_buffer);
    SetInitialized(false);
}

//+------------------------------------------------------------------+
//| Check if Line Renderer is valid                                  |
//+------------------------------------------------------------------+
bool CLineRenderer::IsValid()
{
    return IsInitialized() && ValidateLineParameters() && IsBuffersSetup();
}

//+------------------------------------------------------------------+
//| Set line-specific parameters                                     |
//+------------------------------------------------------------------+
bool CLineRenderer::SetLineParameters(const SLineRendererParams &params)
{
    if(!SetParameters(params.base))
        return false;
    
    m_line_params = params;
    
    // Re-setup buffers if already initialized
    if(IsInitialized())
    {
        if(!SetupBuffers() || !ConfigureDisplay())
            return false;
    }
    
    return ValidateLineParameters();
}

//+------------------------------------------------------------------+
//| Set connect gaps option                                          |
//+------------------------------------------------------------------+
bool CLineRenderer::SetConnectGaps(bool connect)
{
    m_line_params.connect_gaps = connect;
    return true;
}

//+------------------------------------------------------------------+
//| Set show arrows option                                           |
//+------------------------------------------------------------------+
bool CLineRenderer::SetShowArrows(bool show)
{
    m_line_params.show_arrows = show;
    
    // Re-setup buffers if state changed and we're initialized
    if(IsInitialized())
    {
        return SetupBuffers() && ConfigureDisplay();
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Set arrow code                                                   |
//+------------------------------------------------------------------+
bool CLineRenderer::SetArrowCode(int code)
{
    if(code < 0)
        return false;
    
    m_line_params.arrow_code = code;
    
    // Update arrow display if arrows are enabled and we're initialized
    if(IsInitialized() && m_line_params.show_arrows)
    {
        PlotIndexSetInteger(1, PLOT_ARROW, code);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Setup renderer buffers                                           |
//+------------------------------------------------------------------+
bool CLineRenderer::SetupBuffers()
{
    // Determine number of buffers needed
    int buffer_count = 1; // Always need main line buffer
    if(m_line_params.show_arrows)
        buffer_count = 2; // Add arrow buffer
    
    // Allocate indicator buffers
    if(!AllocateBuffers(buffer_count))
        return false;
    
    // Setup main line buffer
    if(!SetupLineBuffer())
        return false;
    
    // Setup arrow buffer if needed
    if(m_line_params.show_arrows)
    {
        if(!SetupArrowBuffer())
            return false;
    }
    
    m_buffers_setup = true;
    return true;
}

//+------------------------------------------------------------------+
//| Configure display settings                                       |
//+------------------------------------------------------------------+
bool CLineRenderer::ConfigureDisplay()
{
    if(!IsBuffersSetup())
        return false;
    
    // Configure main line buffer display
    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, m_params.style.line_color);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, m_params.style.line_width);
    PlotIndexSetInteger(0, PLOT_LINE_STYLE, m_params.style.line_style);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, m_params.style.empty_value);
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, m_params.style.draw_begin);
    PlotIndexSetInteger(0, PLOT_SHIFT, m_params.style.shift);
    PlotIndexSetString(0, PLOT_LABEL, m_params.style.label != "" ? m_params.style.label : "Line");
    
    // Configure arrow buffer display if enabled
    if(m_line_params.show_arrows && m_buffers_count >= 2)
    {
        PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
        PlotIndexSetInteger(1, PLOT_LINE_COLOR, m_params.style.line_color);
        PlotIndexSetInteger(1, PLOT_LINE_WIDTH, m_params.style.line_width);
        PlotIndexSetInteger(1, PLOT_ARROW, m_line_params.arrow_code);
        PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, m_params.style.empty_value);
        PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, m_params.style.draw_begin);
        PlotIndexSetInteger(1, PLOT_SHIFT, m_params.style.shift);
        PlotIndexSetString(1, PLOT_LABEL, "Arrows");
    }
    
    // Set indicator properties
    SetIndicatorDigits(m_params.digits);
    SetIndicatorShortName(m_params.short_name);
    
    return true;
}

//+------------------------------------------------------------------+
//| Update display with new data                                     |
//+------------------------------------------------------------------+
bool CLineRenderer::UpdateDisplay(const double &buffer[], int start_pos, int count)
{
    if(!IsBuffersSetup() || count <= 0)
        return false;
    
    int buffer_size = ArraySize(buffer);
    if(start_pos < 0 || start_pos >= buffer_size)
        return false;
    
    // Copy data to line buffer
    int copy_count = MathMin(count, buffer_size - start_pos);
    int line_buffer_size = ArraySize(m_line_buffer);
    
    // Resize line buffer if needed
    if(line_buffer_size < start_pos + copy_count)
    {
        if(ArrayResize(m_line_buffer, start_pos + copy_count) < 0)
            return false;
    }
    
    // Copy data
    for(int i = 0; i < copy_count; i++)
    {
        m_line_buffer[start_pos + i] = buffer[start_pos + i];
    }
    
    // Process gaps if enabled
    if(!m_line_params.connect_gaps)
    {
        ProcessGaps(m_line_buffer, start_pos, copy_count);
    }
    
    // Update arrows if enabled
    if(m_line_params.show_arrows)
    {
        UpdateArrows(m_line_buffer, m_arrow_buffer, start_pos, copy_count);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Render buffer data                                               |
//+------------------------------------------------------------------+
bool CLineRenderer::RenderBuffer(int buffer_index, const double &data[], int rates_total, int prev_calculated)
{
    if(buffer_index < 0 || buffer_index >= m_buffers_count)
        return false;
    
    if(buffer_index == 0) // Main line buffer
    {
        return UpdateDisplay(data, prev_calculated, rates_total - prev_calculated);
    }
    else if(buffer_index == 1 && m_line_params.show_arrows) // Arrow buffer
    {
        // Arrow buffer is updated automatically when line buffer is updated
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Validate line renderer parameters                                |
//+------------------------------------------------------------------+
bool CLineRenderer::ValidateLineParameters()
{
    if(m_line_params.arrow_code < 0)
        return false;
    
    if(m_line_params.arrow_offset < 0)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Setup main line buffer                                           |
//+------------------------------------------------------------------+
bool CLineRenderer::SetupLineBuffer()
{
    // Set as indicator buffer
    if(!SetIndicatorBuffer(0, m_line_buffer, INDICATOR_DATA))
        return false;
    
    // Initialize with empty values
    ArrayInitialize(m_line_buffer, m_params.style.empty_value);
    ArraySetAsSeries(m_line_buffer, true);
    
    return true;
}

//+------------------------------------------------------------------+
//| Setup arrow buffer                                               |
//+------------------------------------------------------------------+
bool CLineRenderer::SetupArrowBuffer()
{
    if(m_buffers_count < 2)
        return false;
    
    // Set as indicator buffer
    if(!SetIndicatorBuffer(1, m_arrow_buffer, INDICATOR_DATA))
        return false;
    
    // Initialize with empty values
    ArrayInitialize(m_arrow_buffer, m_params.style.empty_value);
    ArraySetAsSeries(m_arrow_buffer, true);
    
    return true;
}

//+------------------------------------------------------------------+
//| Process gaps in line data                                        |
//+------------------------------------------------------------------+
void CLineRenderer::ProcessGaps(double &buffer[], int start_pos, int count)
{
    // This method can be used to handle gaps in data
    // For now, we'll simply ensure empty values are maintained
    for(int i = start_pos; i < start_pos + count; i++)
    {
        if(buffer[i] == 0.0) // Treat zero as empty
            buffer[i] = m_params.style.empty_value;
    }
}

//+------------------------------------------------------------------+
//| Update arrows based on line direction                            |
//+------------------------------------------------------------------+
void CLineRenderer::UpdateArrows(const double &line_buffer[], double &arrow_buffer[], int start_pos, int count)
{
    if(!m_line_params.show_arrows)
        return;
    
    // Resize arrow buffer if needed
    int arrow_buffer_size = ArraySize(arrow_buffer);
    if(arrow_buffer_size < start_pos + count)
    {
        if(ArrayResize(arrow_buffer, start_pos + count) < 0)
            return;
    }
    
    // Generate arrows based on line direction changes
    for(int i = start_pos; i < start_pos + count; i++)
    {
        arrow_buffer[i] = m_params.style.empty_value; // Default to empty
        
        if(i > 0 && 
           line_buffer[i] != m_params.style.empty_value && 
           line_buffer[i-1] != m_params.style.empty_value)
        {
            double current = line_buffer[i];
            double previous = line_buffer[i-1];
            
            // Show arrow on direction change
            if((current > previous && (i == 1 || line_buffer[i-2] >= line_buffer[i-1])) ||
               (current < previous && (i == 1 || line_buffer[i-2] <= line_buffer[i-1])))
            {
                arrow_buffer[i] = current + m_line_params.arrow_offset;
            }
        }
    }
} 