//+------------------------------------------------------------------+
//|                                    Bollinger_Bandwidth_Delta.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                                 https://mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://mql5.com"
#property version   "1.00"
#property description "Bollinger Bandwidth Delta oscillator"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   1
//--- plot BBD
#property indicator_label1  "BBD"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrGreen,clrRed,clrDarkGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
//--- horizontal levels
#property indicator_level1  10
#property indicator_level2  -10
#property indicator_levelcolor clrDarkGray
#property indicator_levelstyle STYLE_DASH
#property indicator_levelwidth 1
//--- enums
enum ENUM_INPUT_YES_NO
  {
   INPUT_YES   =  1, // Yes
   INPUT_NO    =  0  // No
  };
//--- input parameters
input uint                 InpPeriodBB       =  20;            // BB period
input double               InpDeviation      =  2.0;           // BB deviation
input uint                 InpPeriodDelta    =  20;            // Delta period
input ENUM_APPLIED_PRICE   InpAppliedPrice   =  PRICE_CLOSE;   // Applied price
input ENUM_INPUT_YES_NO    InpPercent        =  INPUT_NO;      // Show data in percentage
//--- alert parameters
input ENUM_INPUT_YES_NO    InpAlertEnabled   =  INPUT_NO;      // Enable alerts
input uint                 InpAlertBars      =  3;             // Consecutive bars for range alert
input uint                 InpAlertCooldown  =  10;            // Alert cooldown (bars)
input ENUM_INPUT_YES_NO    InpBarCloseAlert  =  INPUT_NO;      // Enable bar close alerts
//--- indicator buffers
double         BufferBBD[];
double         BufferColors[];
double         BufferWidth[];
double         BufferMA[];
double         BufferDev[];
//--- global variables
double         deviation;
int            period_bb;
int            delta;
int            handle_ma;
int            handle_dev;
//--- alert variables
uint           alert_counter = 0;
uint           cooldown_counter = 0;
bool           alert_triggered = false;
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- set global variables
   period_bb=int(InpPeriodBB<1 ? 1 : InpPeriodBB);
   delta=int(InpPeriodDelta<1 ? 1 : InpPeriodDelta);
   deviation=InpDeviation;
//--- indicator buffers mapping
   SetIndexBuffer(0,BufferBBD,INDICATOR_DATA);
   SetIndexBuffer(1,BufferColors,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,BufferWidth,INDICATOR_CALCULATIONS);
   SetIndexBuffer(3,BufferMA,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,BufferDev,INDICATOR_CALCULATIONS);
//--- setting indicator parameters
   IndicatorSetString(INDICATOR_SHORTNAME,"BB width delta ("+(string)period_bb+","+DoubleToString(deviation,2)+(string)delta+")");
   IndicatorSetInteger(INDICATOR_DIGITS,Digits());
//--- setting plot buffer parameters
   PlotIndexSetInteger(0,PLOT_SHOW_DATA,true);
   PlotIndexSetInteger(2,PLOT_SHOW_DATA,false);
   
//--- setting buffer arrays as timeseries
   ArraySetAsSeries(BufferBBD,true);
   ArraySetAsSeries(BufferColors,true);
   ArraySetAsSeries(BufferWidth,true);
   ArraySetAsSeries(BufferMA,true);
   ArraySetAsSeries(BufferDev,true);
//--- create handles
   ResetLastError();
   handle_ma=iMA(NULL,PERIOD_CURRENT,period_bb,0,MODE_SMA,InpAppliedPrice);
   if(handle_ma==INVALID_HANDLE)
     {
      Print("The iMA(",(string)period_bb,") object was not created: Error ",GetLastError());
      return INIT_FAILED;
     }
   handle_dev=iStdDev(NULL,PERIOD_CURRENT,period_bb,0,MODE_SMA,InpAppliedPrice);
   if(handle_dev==INVALID_HANDLE)
     {
      Print("The iStdDev(",(string)period_bb,") object was not created: Error ",GetLastError());
      return INIT_FAILED;
     }
//---
   return(INIT_SUCCEEDED);
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
//--- Проверка и расчёт количества просчитываемых баров
   if(rates_total<fmax(delta,4) || Point()==0) return 0;
//--- Проверка и расчёт количества просчитываемых баров
   int limit=rates_total-prev_calculated;
   if(limit>1)
     {
      limit=rates_total-delta-2;
      ArrayInitialize(BufferBBD,EMPTY_VALUE);
      ArrayInitialize(BufferColors,2);
      ArrayInitialize(BufferWidth,0);
      ArrayInitialize(BufferMA,0);
      ArrayInitialize(BufferDev,0);
      alert_counter = 0;
      cooldown_counter = 0;
      alert_triggered = false;
     }
//--- Подготовка данных
   int count=(limit>1 ? rates_total : 1),copied=0;
   copied=CopyBuffer(handle_ma,0,0,count,BufferMA);
   if(copied!=count) return 0;
   copied=CopyBuffer(handle_dev,0,0,count,BufferDev);
   if(copied!=count) return 0;

//--- Расчёт индикатора
   for(int i=limit; i>=0 && !IsStopped(); i--)
     {
      if(BufferMA[i]!=0)
        {
         //--- Calculate the normalized bandwidth
         BufferWidth[i]=2*deviation*BufferDev[i]/BufferMA[i];
         if(InpPercent)
            BufferBBD[i]=(BufferWidth[i+delta-1]!=0 ? BufferBBD[i]=100.0*(BufferWidth[i]-BufferWidth[i+delta-1])/BufferWidth[i+delta-1] : 0);
         else
            BufferBBD[i]=(BufferWidth[i]-BufferWidth[i+delta-1])/Point();
        }
      else
        {
         BufferBBD[i]=0;
        }
      BufferColors[i]=(BufferBBD[i]>BufferBBD[i+1] ? 0 : BufferBBD[i]<BufferBBD[i+1] ? 1 : 2);
      
      //--- Alert logic for range-bound detection
      if(InpAlertEnabled == INPUT_YES && i == 0 && cooldown_counter == 0)
        {
         //--- Check if the value is within the range -10 to +10
         if(BufferBBD[i] > -10 && BufferBBD[i] < 10)
            alert_counter++;
         else
            alert_counter = 0;
            
         //--- If we have enough consecutive range-bound bars, trigger alert
         if(alert_counter >= InpAlertBars && !alert_triggered)
           {
            string message = "BBD: Range-bound between -10 and +10 for " + string(alert_counter) + " consecutive bars";
            Alert(message);
            
            //--- Optional: Send mobile notification if enabled
            SendNotification(message);
            
            alert_triggered = true;
            cooldown_counter = InpAlertCooldown;
           }
        }
        
      //--- Bar close alert
      if(InpBarCloseAlert == INPUT_YES && i == 0)
        {
         //--- Format the BBD value with 2 decimal places
         double bbdValue = NormalizeDouble(BufferBBD[i], 2);
         string barColor = (BufferColors[i] == 0) ? "Green" : (BufferColors[i] == 1) ? "Red" : "Gray";
         
         //--- Prepare and send the alert message
         string message = "BBD: Bar closed with value " + DoubleToString(bbdValue, 2) + 
                         " (" + barColor + ")";
         Alert(message);
         
         //--- Optional: Send mobile notification
         SendNotification(message);
        }
     }
     
   //--- Decrease cooldown if active
   if(cooldown_counter > 0)
      cooldown_counter--;
   else if(alert_triggered)
      alert_triggered = false;

//--- return value of prev_calculated for next call
   return(rates_total);
  }
//+------------------------------------------------------------------+