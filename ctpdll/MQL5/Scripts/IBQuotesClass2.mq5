//+------------------------------------------------------------------+
//|                                                     IBQuotes.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#include "..\Include\JAson.mqh"

input string Class = "2";

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

string   G_instrumentsfile = "Class" + Class + "Symbols.json";
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
      
      if (i<3 || res1[0] != "Custom" || res1[1] != provider) {
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

void OnStart()
{
   uchar host[], user[], passwd[], vhost[], msgqname[], vixqname[], recv[1024];
   int ret;
   ulong len = sizeof(recv) - 1;

   GetCustomSymbolsInfo("IB");
   
   StringToCharArray(G_rbmqhost, host);
   StringToCharArray(G_rbmquser, user);
   StringToCharArray(G_rbmqpasswd, passwd);
   StringToCharArray(G_rbmqvhost, vhost);

   ret = rbmqInit(host, G_rbmqport, user, passwd);
	ret = rbmqConnect(vhost);	   
	ret = rbmqOpenChannel(1);

   GetCustomSymbolsInfo("IB");
   
   uchar exchange[],symchar[];
   StringToCharArray("amq.direct", exchange);
   StringToCharArray("RealtimeBar", msgqname);
   StringToCharArray("VIXTick", vixqname);
   ret = rbmqSubscribe(exchange, msgqname, 1, msgqname);
   ret = rbmqSubscribe(exchange, vixqname, 1, vixqname);
	
	while (1) {

		if (rbmqNextMessage(recv, len) == 0) {
		   string recvStr = CharArrayToString(recv);
         CJAVal js(NULL, jtUNDEF);
         js.Deserialize(recvStr);
         
         string cid = js["conid"].ToStr();
         ulong ts = js["ts"].ToInt();
         double price = js["price"].ToDbl();
         string msgType = js["qtype"].ToStr();

         string symbol = GetCustomerSymbolByContractID(cid);
   		if (symbol == "")
   		   continue;
   		if (msgType == "vix")
            symbol = "VIX_" + symbol;
         
         datetime dt = ts / 1000 - TimeGMTOffset();
		   Print("Symbol: " ,symbol, ",time: ", dt, ", price: ", price);


         MqlTick tick[1];
      
         tick[0].ask       = price;
         tick[0].bid       = price;
         tick[0].last      = price;
         tick[0].volume    = 10;
         tick[0].time      = dt;
         tick[0].time_msc  = dt * 1000;
      
         tick[0].flags     = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST | TICK_FLAG_SELL;
      
         ret = CustomTicksAdd(symbol, tick);
         if (ret != 1) {
            Print("更新报价错误码 : '", ret, "' 错误信息:'", GetLastError(), "'");
         }
		}
   	len = sizeof(recv);
	}

	rbmqCloseChannel();
	rbmqCloseConnection();  
}
