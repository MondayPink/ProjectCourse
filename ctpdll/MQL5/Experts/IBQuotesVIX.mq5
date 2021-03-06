//+------------------------------------------------------------------+
//|                                                     IBQuotes.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include "..\Include\JAson.mqh"

#import "rabbitmqenc.dll"
   string rbmqgetHostname();
   int rbmqGetPort();
	int rbmqInit(uchar &host[], int port, uchar &username[], uchar &password[]);
	int rbmqConnect(uchar &vhost[]);
	int rbmqOpenChannel(int no);
	int rbmqSubscribe(uchar &exchange[], uchar &key[], int channel,uchar &queue[]);
	int rbmqPublish(uchar &exchange[], uchar &key[], int channel, uchar &msg[], ulong len);
	int rbmqNextMessage(uchar &msg[], ulong &len);
	int rbmqCloseChannel();
	int rbmqCloseConnection();
#import

string   G_instrumentsfile = "CustomSymbols.json";
string   G_provider = "IB";
string   G_rbmqhost = "localhost";
int      G_rbmqport = 5672;
string   G_rbmquser = "guest";
string   G_rbmqpasswd = "guest";
string   G_rbmqvhost = "/";
string   G_symbols[];
string   G_conids[];

void GetCustomSymbolsInfo(string provider) {

   int c = SymbolsTotal(false);  // 获得所有活跃symbol的个数
   for (int j=0;j<c;j++) {
   
      string sym = SymbolName(j, false);
      string p = SymbolInfoString(sym, SYMBOL_PATH);
      string res1[];
      int i = StringSplit(p, StringGetCharacter("\\", 0), res1);
      
      if (i<2 || (res1[0] != "Custom" && res1[0] != provider)) {
         continue;
      }
      
      ArrayResize(G_symbols, ArraySize(G_symbols) + 1);
      G_symbols[ArraySize(G_symbols) - 1] = sym;
      ArrayResize(G_conids, ArraySize(G_conids) + 1);
      G_conids[ArraySize(G_conids) - 1] = SymbolInfoString(sym, SYMBOL_BASIS);
      
   }
}

string GetCustomerSymbolByContractID(string conid) {
   for (int i=0; i<ArraySize(G_symbols); i++) {
      if (G_conids[i] == conid) 
         return G_symbols[i];
   }
   return "";
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {

   GetCustomSymbolsInfo(G_provider);
   uchar host[], user[], passwd[], vhost[], recv[512] = {0};
   int ret;
   ulong len = sizeof(recv) - 1;
   
   StringToCharArray(G_rbmqhost, host);
   StringToCharArray(G_rbmquser, user);
   StringToCharArray(G_rbmqpasswd, passwd);
   StringToCharArray(G_rbmqvhost, vhost);

   ret = rbmqInit(host, G_rbmqport, user, passwd);
	ret = rbmqConnect(vhost);	   
	ret = rbmqOpenChannel(1);

   uchar exchange[],rtbar[], vixtick[];
   StringToCharArray("amq.direct", exchange);
   StringToCharArray("RealtimeBar", rtbar);
   StringToCharArray("VIXTick", vixtick);
   
	ret = rbmqSubscribe(exchange, rtbar, 1, rtbar);
	ret = rbmqSubscribe(exchange, vixtick, 1, vixtick);
   EventSetTimer(5);
   
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
	rbmqCloseChannel();
	rbmqCloseConnection();   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   string cookie=NULL,headers;
   char post[],result[];
   int res;
   
   string sym = _Symbol;
   string id = SymbolInfoString(sym, SYMBOL_BASIS);
   string url = QuotesHubURL + "?instrument=" + id;
   
   ResetLastError();
   
   int timeout=50000; 

   res=WebRequest("GET", url, cookie, NULL, timeout, post, 0, result, headers);
   
   if(res!=200) {
      Print("Error in WebRequest. Error code  = " + GetLastError());
      return;
   }

   string msg = CharArrayToString(result);

   CJAVal js(NULL, jtUNDEF);
   js.Deserialize(result);

   string httpres = js["res"].ToStr();
   
   if (httpres != "ok") {
      Print("Failed to get quotes data: " + msg);
      return;
   }
   
   double price = js["price"].ToDbl();
   double vix = js["vix"].ToDbl();

   if (price <=0 || vix <=0) {
      Print("Either price or vix is ZERO, skipped. Price=", price, ", VIX=", vix);
      return;
   }
   
   MqlTick tick[1];

   tick[0].ask       = price;
   tick[0].bid       = price;
   tick[0].last      = price;
   tick[0].volume    = 1;
   tick[0].time_msc  = StringToInteger(js["timestamp"].ToStr()) - TimeGMTOffset() * 1000;
   tick[0].time      = tick[0].time_msc / 1000;

   tick[0].flags     = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST | TICK_FLAG_SELL;

   Print("GMT time:", TimeGMT(), ", Quote | bid:", tick[0].bid, ", ask:", tick[0].ask, ", price:", tick[0].last, ", time:", tick[0].time, ", vix:", vix);
   
   res = CustomTicksAdd(_Symbol, tick);
   if (res != 1) {
      Print("更新报价错误码 : '", res, "' 错误信息:'", GetLastError(), "'");
   }
   
   tick[0].ask       = vix;
   tick[0].bid       = vix;
   tick[0].last      = vix;
   
   sym = "VIX_" + _Symbol;
   
   res = CustomTicksAdd(sym, tick);
   if (res != 1) {
      Print(sym, " 更新报价错误码 : '", res, "' 错误信息:'", GetLastError(), "'");
   }

  }
//+------------------------------------------------------------------+
// {'res':'ok', 'timestamp':'1531911296410', 'price': '0.0089000', 'vix': '0.0000'}
// CJAVal{  m_e:[2] m_key:"" m_lkey:"" m_parent:NULL m_type:jtOBJ m_bv:false m_iv:0 m_dv:0.0 m_prec:8 m_sv:"" }