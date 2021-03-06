//+------------------------------------------------------------------+
//|                                                 rabbitmqtest.mq4 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#include "..\Include\JAson.mqh"

struct mt5_quotes_rec {
	uchar instID[31];
	double	Open;
	double	High;
	double	Low;
	uint Volume;
	double	Close;
	ulong timestamp;
};

#import "rabbitmqenc.dll"
   string rbmqgetHostname();
   int rbmqGetPort();
	int rbmqInit(uchar &host[], int port, uchar &username[], uchar &password[]);
	int rbmqConnect(uchar &vhost[]);
	int rbmqOpenChannel(int no);
	int rbmqSubscribe(uchar &exchange[], uchar &key[], int channel,uchar &queue[]);
	int rbmqPublish(uchar &exchange[], uchar &key[], int channel, uchar &msg[], ulong len);
	int rbmqNextMessage(uchar &msg[], ulong &len);
	int rbmqNextMessage(mt5_quotes_rec &msg, ulong &len);
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


//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
  
 //  GetCustomSymbolsInfo(G_provider);
   uchar host[], user[], passwd[], vhost[];
   mt5_quotes_rec recv;
   int ret;
   ulong len = sizeof(recv) - 1;
   
   StringToCharArray(G_rbmqhost, host);
   StringToCharArray(G_rbmquser, user);
   StringToCharArray(G_rbmqpasswd, passwd);
   StringToCharArray(G_rbmqvhost, vhost);

   ret = rbmqInit(host, G_rbmqport, user, passwd);
	ret = rbmqConnect(vhost);	   
	ret = rbmqOpenChannel(2);

   GetCustomSymbolsInfo("CTP");
   
   uchar exchange[],symchar[];
   StringToCharArray("amq.direct", exchange);
   
   for (int i=0;i<ArraySize(G_symbols); i++) {
      StringToCharArray("CTP_QUOTES_" + G_symbols[i], symchar);
   	ret = rbmqSubscribe(exchange, symchar, 2, symchar);
   }
	
	while (1) {

		if (rbmqNextMessage(recv, len) == 0) {
		   datetime dt = recv.timestamp - TimeGMTOffset();
		   Print("ID: " ,CharArrayToString(recv.instID), ",time: ", dt, ", open: ", recv.Open, ", price: ", recv.Close);

   		string symbol = CharArrayToString(recv.instID);
   		if (symbol == "") continue;

         MqlTick tick[1];
      
         tick[0].ask       = recv.Close;
         tick[0].bid       = recv.Close;
         tick[0].last      = recv.Close;
         tick[0].volume    = recv.Volume;
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
//+------------------------------------------------------------------+
