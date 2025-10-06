//+------------------------------------------------------------------+
//|                                        Custom Moving Average.mq5 |
//|                        Copyright 2009, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "2009, MetaQuotes Software Corp."
#property link      "http://www.mql5.com"

//--- indicator settings
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_type1   DRAW_LINE
#property indicator_type2   DRAW_LINE
#property indicator_color1  clrMediumAquamarine
#property indicator_color2  clrDimGray
#property indicator_width1  1
#property indicator_width2  1
//--- input parameters
input int            InpFastMAPeriod=12;         // Fast MA Period
input int            InpSlowMAPeriod=48;         // Slow MA Period
input int            InpMAShift=0;               // Shift
input ENUM_MA_METHOD InpMAMethod=MODE_SMA;       // Method
//--- indicator buffers
double               ExtFastLineBuffer[];
double               ExtSlowLineBuffer[];
//+------------------------------------------------------------------+
//|   simple moving average                                          |
//+------------------------------------------------------------------+
void CalculateSimpleMA(int rates_total,int prev_calculated,int begin,const double &price[],
                      double &buffer[],int period)
  {
   int i,limit;
//--- first calculation or number of bars was changed
   if(prev_calculated==0)// first calculation
     {
      limit=period+begin;
      //--- set empty value for first limit bars
      for(i=0;i<limit-1;i++) buffer[i]=0.0;
      //--- calculate first visible value
      double firstValue=0;
      for(i=begin;i<limit;i++)
         firstValue+=price[i];
      firstValue/=period;
      buffer[limit-1]=firstValue;
     }
   else limit=prev_calculated-1;
//--- main loop
   for(i=limit;i<rates_total && !IsStopped();i++)
      buffer[i]=buffer[i-1]+(price[i]-price[i-period])/period;
//---
  }
//+------------------------------------------------------------------+
//|  exponential moving average                                      |
//+------------------------------------------------------------------+
void CalculateEMA(int rates_total,int prev_calculated,int begin,const double &price[],
                 double &buffer[],int period)
  {
   int    i,limit;
   double SmoothFactor=2.0/(1.0+period);
//--- first calculation or number of bars was changed
   if(prev_calculated==0)
     {
      limit=period+begin;
      buffer[begin]=price[begin];
      for(i=begin+1;i<limit;i++)
         buffer[i]=price[i]*SmoothFactor+buffer[i-1]*(1.0-SmoothFactor);
     }
   else limit=prev_calculated-1;
//--- main loop
   for(i=limit;i<rates_total && !IsStopped();i++)
      buffer[i]=price[i]*SmoothFactor+buffer[i-1]*(1.0-SmoothFactor);
//---
  }
//+------------------------------------------------------------------+
//|  linear weighted moving average                                  |
//+------------------------------------------------------------------+
void CalculateLWMA(int rates_total,int prev_calculated,int begin,const double &price[],
                  double &buffer[],int period)
  {
   int        i,limit;
   int        weightsum=0;
   double     sum;
//--- calculate weight sum
   for(i=1;i<=period;i++)
      weightsum+=i;
//--- first calculation or number of bars was changed
   if(prev_calculated==0)
     {
      limit=period+begin;
      //--- set empty value for first limit bars
      for(i=0;i<limit;i++) buffer[i]=0.0;
      //--- calculate first visible value
      double firstValue=0;
      for(i=begin;i<limit;i++)
        {
         int k=i-begin+1;
         firstValue+=k*price[i];
        }
      firstValue/=(double)weightsum;
      buffer[limit-1]=firstValue;
     }
   else limit=prev_calculated-1;
//--- main loop
   for(i=limit;i<rates_total && !IsStopped();i++)
     {
      sum=0;
      for(int j=0;j<period;j++) sum+=(period-j)*price[i-j];
      buffer[i]=sum/weightsum;
     }
//---
  }
//+------------------------------------------------------------------+
//|  smoothed moving average                                         |
//+------------------------------------------------------------------+
void CalculateSmoothedMA(int rates_total,int prev_calculated,int begin,const double &price[],
                        double &buffer[],int period)
  {
   int i,limit;
//--- first calculation or number of bars was changed
   if(prev_calculated==0)
     {
      limit=period+begin;
      //--- set empty value for first limit bars
      for(i=0;i<limit-1;i++) buffer[i]=0.0;
      //--- calculate first visible value
      double firstValue=0;
      for(i=begin;i<limit;i++)
         firstValue+=price[i];
      firstValue/=period;
      buffer[limit-1]=firstValue;
     }
   else limit=prev_calculated-1;
//--- main loop
   for(i=limit;i<rates_total && !IsStopped();i++)
      buffer[i]=(buffer[i-1]*(period-1)+price[i])/period;
//---
  }
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void OnInit()
  {
//--- indicator buffers mapping
   SetIndexBuffer(0,ExtFastLineBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,ExtSlowLineBuffer,INDICATOR_DATA);
//--- set accuracy
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits+1);
//--- sets first bar from what index will be drawn
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,InpFastMAPeriod);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,InpSlowMAPeriod);
//---- line shifts when drawing
   PlotIndexSetInteger(0,PLOT_SHIFT,InpMAShift);
   PlotIndexSetInteger(1,PLOT_SHIFT,InpMAShift);
//--- name for DataWindow
   string short_name="unknown ma";
   switch(InpMAMethod)
     {
      case MODE_EMA :  short_name="EMA";  break;
      case MODE_LWMA : short_name="LWMA"; break;
      case MODE_SMA :  short_name="SMA";  break;
      case MODE_SMMA : short_name="SMMA"; break;
     }
   IndicatorSetString(INDICATOR_SHORTNAME,short_name+"("+string(InpFastMAPeriod)+","+string(InpSlowMAPeriod)+")");
//---- sets drawing line empty value
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,0.0);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,0.0);
//---- initialization done
  }
//+------------------------------------------------------------------+
//|  Moving Average                                                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
  {
//--- check for bars count (using the longer period)
   if(rates_total<InpSlowMAPeriod-1+begin)
      return(0);// not enough bars for calculation
//--- first calculation or number of bars was changed
   if(prev_calculated==0)
     {
      ArrayInitialize(ExtFastLineBuffer,0);
      ArrayInitialize(ExtSlowLineBuffer,0);
     }
//--- sets first bar from what index will be drawn
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,InpFastMAPeriod-1+begin);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,InpSlowMAPeriod-1+begin);

//--- calculation for both fast and slow MAs
   switch(InpMAMethod)
     {
      case MODE_EMA:
         CalculateEMA(rates_total,prev_calculated,begin,price,ExtFastLineBuffer,InpFastMAPeriod);
         CalculateEMA(rates_total,prev_calculated,begin,price,ExtSlowLineBuffer,InpSlowMAPeriod);
         break;
      case MODE_LWMA:
         CalculateLWMA(rates_total,prev_calculated,begin,price,ExtFastLineBuffer,InpFastMAPeriod);
         CalculateLWMA(rates_total,prev_calculated,begin,price,ExtSlowLineBuffer,InpSlowMAPeriod);
         break;
      case MODE_SMMA:
         CalculateSmoothedMA(rates_total,prev_calculated,begin,price,ExtFastLineBuffer,InpFastMAPeriod);
         CalculateSmoothedMA(rates_total,prev_calculated,begin,price,ExtSlowLineBuffer,InpSlowMAPeriod);
         break;
      case MODE_SMA:
      default:
         CalculateSimpleMA(rates_total,prev_calculated,begin,price,ExtFastLineBuffer,InpFastMAPeriod);
         CalculateSimpleMA(rates_total,prev_calculated,begin,price,ExtSlowLineBuffer,InpSlowMAPeriod);
         break;
     }
//--- return value of prev_calculated for next call
   return(rates_total);
  }
//+------------------------------------------------------------------+