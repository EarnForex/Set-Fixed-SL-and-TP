#property link          "https://www.earnforex.com/metatrader-scripts/set-fixed-sl-tp/"
#property version       "1.01"
#property strict
#property copyright     "EarnForex.com - 2023"
#property description   "This script sets a stop-loss and, if required a take-profit, to all open orders based on filters."
#property description   "SL and TP values are in POINTS (not pips)."
#property description   ""
#property description   "DISCLAIMER: This script comes with no guarantee. Use it at your own risk."
#property description   "It is best to test it on a demo account first."
#property icon          "\\Files\\EF-Icon-64x64px.ico"
#property show_inputs

enum ENUM_PRICE_TYPE
{
    ENUM_PRICE_TYPE_OPEN, // Trade's open price
    ENUM_PRICE_TYPE_CURRENT // Current price
};

enum ENUM_ORDER_TYPES
{
    ALL_ORDERS = 1, // ALL TRADES
    ONLY_BUY = 2,   // BUY ONLY
    ONLY_SELL = 3   // SELL ONLY
};

input int StopLoss = 200;             // Stop-Loss in points
input int TakeProfit = 400;           // Take-Profit in points
input bool CurrentSymbolOnly = true;  // Current symbol only?
input ENUM_ORDER_TYPES OrderTypeFilter = ALL_ORDERS; // Type of trades to apply to
input bool OnlyMagicNumber = false;   // Modify only trades matching the magic number
input int MagicNumber = 0;            // Matching magic number
input bool OnlyWithComment = false;   // Modify only trades with the following comment
input string MatchingComment = "";    // Matching comment
input int Delay = 0;                  // Delay to wait between modifying trades (in milliseconds)
input ENUM_PRICE_TYPE PriceType = ENUM_PRICE_TYPE_OPEN; // Price to use for SL/TP setting
input bool ApplyToPending = false;    // Apply to pending orders too?

void OnStart()
{
    if (!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        Print("Not connected to the trading server. Exiting.");
        return;
    }

    if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!MQLInfoInteger(MQL_TRADE_ALLOWED)))
    {
        Print("Autotrading is disable. Please enable. Exiting.");
        return;
    }

    if ((StopLoss == 0) && (TakeProfit == 0))
    {
        Print("Both StopLoss and TakeProfit are set to zero. Exiting.");
        return;
    }

    int TotalModified = 0;
    
    // Scan the orders backwards:
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        // Select the order. If not selected print the error and continue with the next index.
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false)
        {
            Print("ERROR - Unable to select the order - ", GetLastError());
            continue;
        }

        // Check if the order can be modified matching the criteria. If criteria not matched skip to the next.
        if ((CurrentSymbolOnly) && (OrderSymbol() != Symbol())) continue;
        if ((OnlyMagicNumber) && (OrderMagicNumber() != MagicNumber)) continue;
        if ((OnlyWithComment) && (StringCompare(OrderComment(), MatchingComment) != 0)) continue;
        if ((!ApplyToPending) && (OrderType() != OP_BUY) && (OrderType() != OP_SELL)) continue;
        if ((OrderTypeFilter == ONLY_SELL) && ((OrderType() ==  OP_BUY) || (OrderType() ==  OP_BUYLIMIT) || (OrderType() ==  OP_BUYSTOP))) continue;
        if ((OrderTypeFilter == ONLY_BUY)  && ((OrderType() == OP_SELL) || (OrderType() == OP_SELLLIMIT) || (OrderType() == OP_SELLSTOP))) continue;
                
        // Prepare everything.
        string symbol = OrderSymbol();
        double TakeProfitPrice = 0;
        double StopLossPrice = 0;
        double Price;
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

        if (SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("Trading is disabled for ", symbol, ". Skipping.");
            continue;
        }

        double tick_size = MarketInfo(OrderSymbol(), MODE_TICKSIZE);
        if (tick_size == 0)
        {
            Print("Zero tick size for ", symbol, ". Skipping.");
            continue;
        }

        if ((OrderType() == OP_BUY) || (OrderType() == OP_BUYLIMIT) || (OrderType() == OP_BUYSTOP))
        {
            if (PriceType == ENUM_PRICE_TYPE_CURRENT)
            {
                RefreshRates();
                // Should be Bid for Buy orders:
                Price = SymbolInfoDouble(symbol, SYMBOL_BID);
            }
            else Price = OrderOpenPrice();
            if (TakeProfit > 0)
            {
                TakeProfitPrice = NormalizeDouble(Price + TakeProfit * point, digits);
                TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
            }
            else TakeProfitPrice = OrderTakeProfit();
            if (StopLoss > 0)
            {
                StopLossPrice = NormalizeDouble(Price - StopLoss * point, digits);
                StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
            }
            else StopLossPrice = OrderStopLoss();
        }
        else if ((OrderType() == OP_SELL) || (OrderType() == OP_SELLLIMIT) || (OrderType() == OP_SELLSTOP))
        {
            if (PriceType == ENUM_PRICE_TYPE_CURRENT)
            {
                RefreshRates();
                // Should be Ask for Sell orders:
                Price = SymbolInfoDouble(symbol, SYMBOL_ASK);
            }
            else Price = OrderOpenPrice();
            if (TakeProfit > 0)
            {
                TakeProfitPrice = NormalizeDouble(Price - TakeProfit * point, digits);
                TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
            }
            else TakeProfitPrice = OrderTakeProfit();
            if (StopLoss > 0)
            {
                StopLossPrice = NormalizeDouble(Price + StopLoss * point, digits);
                StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
            }
            else StopLossPrice = OrderStopLoss();
        }

        // Try to modify the order:
        if (OrderModify(OrderTicket(), OrderOpenPrice(), StopLossPrice, TakeProfitPrice, OrderExpiration()))
        {
            TotalModified++;
        }
        else
        {
            Print("Order failed to update with error - ", GetLastError());
        }

        // Wait if necessary.
        Sleep(Delay);
    }

    Print("Total orders modified = ", TotalModified);
}
//+------------------------------------------------------------------+