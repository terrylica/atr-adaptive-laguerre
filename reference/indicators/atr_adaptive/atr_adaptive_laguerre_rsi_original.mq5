//------------------------------------------------------------------
#property copyright "© mladen 2021"
#property link      "mladenfx@gmail.com"
//------------------------------------------------------------------
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   1
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrGray,clrDodgerBlue,clrTomato
#property indicator_width1  2

//
//---
//

input int                inpAtrPeriod   = 32;             // ATR period
input ENUM_APPLIED_PRICE inpRsiPrice    = PRICE_CLOSE;    // Price
input int                inpRsiMaPeriod = 5;              // Price smoothing period
input ENUM_MA_METHOD     inpRsiMaType   = MODE_EMA;       // Price smoothing method
input double             inpLevelUp     = 0.85;           // Level up
input double             inpLevelDown   = 0.15;           // Level down

//
//
//

double val[],valc[],prices[];
struct sGlobalStruct
  {
   int               maHandle;
   int               maPeriod;
  };
sGlobalStruct global;

//------------------------------------------------------------------
//
//------------------------------------------------------------------
//
//
//

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,val,INDICATOR_DATA);
   SetIndexBuffer(1,valc,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,prices,INDICATOR_CALCULATIONS);
   IndicatorSetInteger(INDICATOR_LEVELS,2);
   IndicatorSetDouble(INDICATOR_LEVELVALUE,0,inpLevelUp);
   IndicatorSetDouble(INDICATOR_LEVELVALUE,1,inpLevelDown);

   global.maPeriod = MathMax(inpRsiMaPeriod,1);
   global.maHandle = iMA(_Symbol,_Period,global.maPeriod,0,inpRsiMaType,inpRsiPrice);

//
//
//

   IndicatorSetString(INDICATOR_SHORTNAME,"ATR adaptive Laguerre RSI ("+(string)inpAtrPeriod+","+(string)inpRsiMaPeriod+")");
   return(0);
  }

//------------------------------------------------------------------
//
//------------------------------------------------------------------
//
//
//

//+------------------------------------------------------------------+
//|                                                                  |
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
   int limit     = (prev_calculated>0) ? prev_calculated-1 : 0;
   int copyCount = (prev_calculated>0) ? rates_total-prev_calculated+1 : rates_total;
   if(CopyBuffer(global.maHandle,0,0,copyCount,prices)!=copyCount)
      return(prev_calculated);

//
//
//

   struct sWorkStruct
     {
      double         tr;
      double         trSum;
      double         atr;
      double         prevMin;
      double         prevMax;
      int            saveBar;
                     sWorkStruct() : saveBar(-1) {};
     };
   static sWorkStruct m_work[];
   static int         m_workSize = -1;
   if(m_workSize<=rates_total)
      m_workSize = ArrayResize(m_work,rates_total+500,2000);

//
//
//

   for(int i=limit; i<rates_total && !_StopFlag; i++)
     {
      if(prices[i]==EMPTY_VALUE)
         prices[i]=close[i];

      //
      //
      //

      m_work[i].tr = (i>0) ? (high[i]>close[i-1] ? high[i] : close[i-1]) -(low[i]<close[i-1] ? low[i] : close[i-1]) : high[i]-low[i];
      if(i>inpAtrPeriod)
         m_work[i].trSum = m_work[i-1].trSum + m_work[i].tr - m_work[i-inpAtrPeriod].tr;
      else
        {
         m_work[i].trSum = m_work[i].tr;
         for(int k=1; k<inpAtrPeriod && i>=k; k++)
            m_work[i].trSum += m_work[i-k].tr;
        }
      m_work[i].atr   = m_work[i].trSum/(double)inpAtrPeriod;

      //
      //
      //

      if(m_work[i].saveBar!=i || m_work[i+1].saveBar>=i)
        {
         m_work[i  ].saveBar = i;
         m_work[i+1].saveBar =-1;
         if(inpAtrPeriod>1 && i>0)
           {
            m_work[i].prevMax =
               m_work[i].prevMin = m_work[i-1].atr;
            for(int k=2; k<inpAtrPeriod && i>=k; k++)
              {
               if(m_work[i-k].atr > m_work[i].prevMax)
                  m_work[i].prevMax = m_work[i-k].atr;
               if(m_work[i-k].atr < m_work[i].prevMin)
                  m_work[i].prevMin = m_work[i-k].atr;
              }
           }
         else
            m_work[i].prevMax = m_work[i].prevMin = m_work[i].atr;
        }

      //
      //
      //

      double _max   = m_work[i].prevMax > m_work[i].atr ? m_work[i].prevMax : m_work[i].atr;
      double _min   = m_work[i].prevMin < m_work[i].atr ? m_work[i].prevMin : m_work[i].atr;
      double _coeff = (_min!=_max) ? 1.0-(m_work[i].atr-_min)/(_max-_min) : 0.5;

      val[i]  = iLaGuerreRsi(prices[i],inpAtrPeriod*(_coeff+0.75),i,rates_total);
      valc[i] = (val[i]>inpLevelUp) ? 1 : (val[i]<inpLevelDown) ? 2 : 0;
     }

//
//
//

   return(rates_total);
  }

//------------------------------------------------------------------
//
//------------------------------------------------------------------
//
//
//

#define _lagRsiInstances 1
double iLaGuerreRsi(double price, double period, int i, int bars, int instance=0)
  {
   struct sDataStruct
     {
      double         values[4];
     };
   struct sWorkStruct { sDataStruct data[_lagRsiInstances]; };
   static sWorkStruct m_work[];
   static int         m_workSize = -1;
   if(m_workSize<bars)
      m_workSize = ArrayResize(m_work,bars+500,2000);

//
//
//

   double CU = 0;
   double CD = 0;

   if(i>0 && period>1)
     {
      double _gamma = 1.0 - 10.0/(period+9.0);

      m_work[i].data[instance].values[0] = price                                + _gamma*(m_work[i-1].data[instance].values[0] - price);
      m_work[i].data[instance].values[1] = m_work[i-1].data[instance].values[0] + _gamma*(m_work[i-1].data[instance].values[1] - m_work[i].data[instance].values[0]);
      m_work[i].data[instance].values[2] = m_work[i-1].data[instance].values[1] + _gamma*(m_work[i-1].data[instance].values[2] - m_work[i].data[instance].values[1]);
      m_work[i].data[instance].values[3] = m_work[i-1].data[instance].values[2] + _gamma*(m_work[i-1].data[instance].values[3] - m_work[i].data[instance].values[2]);

      //
      //
      //

      if(m_work[i].data[instance].values[0] >= m_work[i].data[instance].values[1])
         CU =  m_work[i].data[instance].values[0] - m_work[i].data[instance].values[1];
      else
         CD =  m_work[i].data[instance].values[1] - m_work[i].data[instance].values[0];
      if(m_work[i].data[instance].values[1] >= m_work[i].data[instance].values[2])
         CU += m_work[i].data[instance].values[1] - m_work[i].data[instance].values[2];
      else
         CD += m_work[i].data[instance].values[2] - m_work[i].data[instance].values[1];
      if(m_work[i].data[instance].values[2] >= m_work[i].data[instance].values[3])
         CU += m_work[i].data[instance].values[2] - m_work[i].data[instance].values[3];
      else
         CD += m_work[i].data[instance].values[3] - m_work[i].data[instance].values[2];
     }
   else
      for(int k=0; k<4; k++)
         m_work[i].data[instance].values[k]=price;
   return((CU+CD!=0) ? CU/(CU+CD) : 0);
  }
//+------------------------------------------------------------------+
