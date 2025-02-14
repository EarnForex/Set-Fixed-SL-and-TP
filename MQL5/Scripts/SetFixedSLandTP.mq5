#property link          "https://www.earnforex.com/metatrader-scripts/set-fixed-sl-tp/"
#property version       "1.02"

#property copyright     "EarnForex.com - 2023-2025"
#property description   "This script sets a stop-loss and, if required a take-profit, to all open trades based on filters."
#property description   "SL and TP values are in POINTS (not pips)."
#property description   ""
#property description   "DISCLAIMER: This script comes with no guarantee. Use it at your own risk."
#property description   "It is best to test it on a demo account first."
#property icon          "\\Files\\EF-Icon-64x64px.ico"
#property script_show_inputs

#include <Trade/Trade.mqh>

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
input bool SLUseLevelInsteadofPoints = false; // Use level instead of points for SL
input double StopLossLevel = 0;       // Stop-Loss level
input bool LeaveStopLossUnchanged = false; // Leave stop-loss unchanged
input int TakeProfit = 400;           // Take-Profit in points
input bool TPUseLevelInsteadofPoints = false; // Use level instead of points for TP
input double TakeProfitLevel = 0;     // Take-Profit level
input bool LeaveTakeProfitUnchanged = false; // Leave take-profit unchanged
input bool CurrentSymbolOnly = true;  // Current symbol only?
input ENUM_ORDER_TYPES OrderTypeFilter = ALL_ORDERS; // Type of trades to apply to
input bool OnlyMagicNumber = false;   // Modify only orders matching the magic number
input int MagicNumber = 0;            // Matching magic number
input bool OnlyWithComment = false;   // Modify only trades with the following comment
input string MatchingComment = "";    // Matching comment
input int Delay = 0;                  // Delay to wait between modifying trades (in milliseconds)
input ENUM_PRICE_TYPE PriceType = ENUM_PRICE_TYPE_OPEN; // Price to use for SL/TP setting
input bool ApplyToPending = false;    // Apply to pending orders too?
input int AttemptsNumber = 1;         // Number of attempts for trade modification

void OnStart()
{
    if (!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        Print("Not connected to the trading server. Exiting.");
        return;
    }

    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Print("Autotrading is disabled in the platform's options. Please enable. Exiting.");
        return;
    }

    if (!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("Autotrading is disabled in the script's options. Please enable. Exiting.");
        return;
    }

    int TotalModifiedPositions = 0;
    int TotalModifiedOrders = 0;
    CTrade *Trade;
    Trade = new CTrade;

    int positions_total = PositionsTotal();
    for (int i = positions_total - 1; i >= 0; i--) // Going backwards in case one or more positions are closed during the cycle.
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0)
        {
            Print("ERROR - Unable to select the position - ", GetLastError());
            continue;
        }
        
        // Check if the position matches the filter and if not, skip the position and move to the next one.
        if ((OrderTypeFilter == ONLY_SELL) && (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) continue;
        if ((OrderTypeFilter == ONLY_BUY)  && (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) continue;
        if ((CurrentSymbolOnly) && (PositionGetString(POSITION_SYMBOL) != Symbol())) continue;
        if ((OnlyMagicNumber) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
        if ((OnlyWithComment) && (StringCompare(PositionGetString(POSITION_COMMENT), MatchingComment) != 0)) continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

        if (SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("Trading is disabled for ", symbol, ". Skipping.");
            continue;
        }
        
        double Price;
        double TakeProfitPrice = 0;
        double StopLossPrice = 0;
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        if (tick_size == 0)
        {
            Print("Zero tick size for ", symbol, ". Skipping.");
            continue;
        }
        
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if (PriceType == ENUM_PRICE_TYPE_CURRENT)
            {
                // Should be Bid for Buy orders:
                Price = SymbolInfoDouble(symbol, SYMBOL_BID);
            }
            else Price = PositionGetDouble(POSITION_PRICE_OPEN);

            // Take-profit:
            if (LeaveTakeProfitUnchanged)
            {
                TakeProfitPrice = PositionGetDouble(POSITION_TP);
            }
            else if (TPUseLevelInsteadofPoints)
            {
                TakeProfitPrice = TakeProfitLevel;
            }
            else
            {
                if (TakeProfit > 0)
                {
                    TakeProfitPrice = NormalizeDouble(Price + TakeProfit * point, digits);
                    TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                }
                else TakeProfitPrice = 0;
            }
            // Stop-loss:
            if (LeaveStopLossUnchanged)
            {
                StopLossPrice = PositionGetDouble(POSITION_SL);
            }
            else if (SLUseLevelInsteadofPoints)
            {
                StopLossPrice = StopLossLevel;
            }
            else
            {
                if (StopLoss > 0)
                {
                    StopLossPrice = NormalizeDouble(Price - StopLoss * point, digits);
                    StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                }
                else StopLossPrice = 0;
            }
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (PriceType == ENUM_PRICE_TYPE_CURRENT)
            {
                // Should be Ask for Sell orders:
                Price = SymbolInfoDouble(symbol, SYMBOL_ASK);
            }
            else Price = PositionGetDouble(POSITION_PRICE_OPEN);
            
            // Take-profit:
            if (LeaveTakeProfitUnchanged)
            {
                TakeProfitPrice = PositionGetDouble(POSITION_TP);
            }
            else if (TPUseLevelInsteadofPoints)
            {
                TakeProfitPrice = TakeProfitLevel;
																																				  
            }
            else
            {
                if (TakeProfit > 0)
                {
                    TakeProfitPrice = NormalizeDouble(Price - TakeProfit * point, digits);
                    TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                }
                else TakeProfitPrice = 0;
            }
            // Stop-loss:
            if (LeaveStopLossUnchanged)
            {
                StopLossPrice = PositionGetDouble(POSITION_SL);
            }
            else if (SLUseLevelInsteadofPoints)
            {
                StopLossPrice = StopLossLevel;
            }
            else
            {
                if (StopLoss > 0)
                {
                    StopLossPrice = NormalizeDouble(Price + StopLoss * point, digits);
                    StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                }
                else StopLossPrice = 0;
            }
        }

        // Avoid modifying to the same values:
        if ((MathAbs(StopLossPrice - PositionGetDouble(POSITION_SL)) < point / 2) && (MathAbs(TakeProfitPrice - PositionGetDouble(POSITION_TP)) < point / 2)) continue; // Nothing to change (double-safe comparison).

        for (int j = 0; j < AttemptsNumber; j++)
        {
            // Try to modify the position:
            if (!Trade.PositionModify(ticket, StopLossPrice, TakeProfitPrice))
            {
                Print("PositionModify failed: error ", GetLastError(),  " for ", symbol, ", position #", ticket, " while updating SL to ", StopLossPrice, " and TP to ", TakeProfitPrice);
                Sleep(Delay);
            }
            else
            {
                TotalModifiedPositions++;
                Sleep(Delay);
                break;
            }
        }
    }    
    Print("Total positions modified = ", TotalModifiedPositions);

    if (ApplyToPending)
    {
        int orders_total = OrdersTotal();
        for (int i = orders_total - 1; i >= 0; i--) // Going backwards in case one or more orders are deleted during the cycle.
        {
            ulong ticket = OrderGetTicket(i);
            if (ticket <= 0)
            {
                Print("ERROR - Unable to select the position - ", GetLastError());
                continue;
            }
            
            // Check if the position matches the filter and if not, skip the position and move to the next one.
            if ((OrderTypeFilter == ONLY_SELL) && (OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_SELL_STOP) && (OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_SELL_LIMIT) && (OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_SELL_STOP_LIMIT)) continue;
            if ((OrderTypeFilter == ONLY_BUY)  && (OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_STOP) && (OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT) && (OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_STOP_LIMIT)) continue;
            if ((CurrentSymbolOnly) && (OrderGetString(ORDER_SYMBOL) != Symbol())) continue;
            if ((OnlyMagicNumber) && (OrderGetInteger(ORDER_MAGIC) != MagicNumber)) continue;
            if ((OnlyWithComment) && (StringCompare(OrderGetString(ORDER_COMMENT), MatchingComment) != 0)) continue;
    
            string symbol = OrderGetString(ORDER_SYMBOL);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
            if (SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
            {
                Print("Trading is disabled for ", symbol, ". Skipping.");
                continue;
            }
            
            double Price;
            double TakeProfitPrice = 0;
            double StopLossPrice = 0;
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
            if (tick_size == 0)
            {
                Print("Zero tick size for ", symbol, ". Skipping.");
                continue;
            }
            
            if ((OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) || (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) || (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP_LIMIT))
            {
                if (PriceType == ENUM_PRICE_TYPE_CURRENT)
                {
                    // Should be Bid for Buy orders:
                    Price = SymbolInfoDouble(symbol, SYMBOL_BID);
                }
                else Price = OrderGetDouble(ORDER_PRICE_OPEN);

                // Take-profit:
                if (LeaveTakeProfitUnchanged)
                {
                    TakeProfitPrice = OrderGetDouble(ORDER_TP);
    																																					  
                }
                else if (TPUseLevelInsteadofPoints)
    							 
                {
                    TakeProfitPrice = TakeProfitLevel;
    																																				  
                }
                else
                {
                    if (TakeProfit > 0)
                    {
                        TakeProfitPrice = NormalizeDouble(Price + TakeProfit * point, digits);
                        TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                    }
                    else TakeProfitPrice = 0;
                }
                // Stop-loss:
                if (LeaveStopLossUnchanged)
                {
                    StopLossPrice = OrderGetDouble(ORDER_SL);
                }
                else if (SLUseLevelInsteadofPoints)
                {
                    StopLossPrice = StopLossLevel;
                }
                else
                {
                    if (StopLoss > 0)
                    {
                        StopLossPrice = NormalizeDouble(Price - StopLoss * point, digits);
                        StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                    }
                    else StopLossPrice = 0;
                }
            }
            else if ((OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) || (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT) || (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP_LIMIT))
            {
                if (PriceType == ENUM_PRICE_TYPE_CURRENT)
                {
                    // Should be Ask for Sell orders:
                    Price = SymbolInfoDouble(symbol, SYMBOL_ASK);
                }
                else Price = OrderGetDouble(ORDER_PRICE_OPEN);
                
                // Take-profit:
                if (LeaveTakeProfitUnchanged)
                {
                    TakeProfitPrice = OrderGetDouble(ORDER_TP);
    																																					  
                }
                else if (TPUseLevelInsteadofPoints)
    							 
                {
                    TakeProfitPrice = TakeProfitLevel;
    																																				  
                }
                else
                {
                    if (TakeProfit > 0)
                    {
                        TakeProfitPrice = NormalizeDouble(Price - TakeProfit * point, digits);
                        TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                    }
                    else TakeProfitPrice = 0;
                }
                // Stop-loss:
                if (LeaveStopLossUnchanged)
                {
                    StopLossPrice = OrderGetDouble(ORDER_SL);
                }
                else if (SLUseLevelInsteadofPoints)
                {
                    StopLossPrice = StopLossLevel;
                }
                else
                {
                    if (StopLoss > 0)
                    {
                        StopLossPrice = NormalizeDouble(Price + StopLoss * point, digits);
                        StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / tick_size) * tick_size, digits); // Adjusting for tick size granularity.
                    }
                    else StopLossPrice = 0;
                }
            }

            // Avoid modifying to the same values:
            if ((MathAbs(StopLossPrice - OrderGetDouble(ORDER_SL)) < point / 2) && (MathAbs(TakeProfitPrice - OrderGetDouble(ORDER_TP)) < point / 2)) continue; // Nothing to change (double-safe comparison).

            for (int j = 0; j < AttemptsNumber; j++)
            {
                // Try to modify the order:
                if (!Trade.OrderModify(ticket, OrderGetDouble(ORDER_PRICE_OPEN), StopLossPrice, TakeProfitPrice, (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME), OrderGetInteger(ORDER_TIME_EXPIRATION)))
                {
                    Print("OrderModify failed ", GetLastError(),  " for ", symbol, ", order #", ticket, " while updating SL to ", StopLossPrice, " and TP to ", TakeProfitPrice);
                    Sleep(Delay);
                }
                else
                {
                    TotalModifiedOrders++;
                    Sleep(Delay);
                    break;
                }
            }
        }    
        Print("Total orders modified = ", TotalModifiedOrders);
    }

    delete Trade;
}
//+------------------------------------------------------------------+