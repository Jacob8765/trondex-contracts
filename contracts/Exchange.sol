/*
* Copyright 2018 Jacob Schuster <admin@trondex.exchange>
*/

pragma solidity ^0.4.23;

import "./TRC20.sol";

contract Exchange {
    address adminAddress;

    struct tradeStruct {
        address tradeAddress;
        uint quantity;
        uint filled;
        string tradeHash;
    }

    mapping(address => mapping(uint => tradeStruct[])) public buyOrders; //Maps the token address to the buy price to the order id
    mapping(address => mapping(uint => tradeStruct[])) public sellOrders; //Maps the token address to the sell price to the order id
    
    event buyOrderEvent(address tokenAddress, uint id, /* uint tradesFromAddressId, */ uint price, uint quantity, uint filled, string tradeType, string tradeHash, address tradeAddress);
    event sellOrderEvent(address tokenAddress, uint id, /* uint tradesFromAddressId, */ uint price, uint quantity, uint filled, string tradeType, string tradeHash, address tradeAddress);
    event CompleteTrade(address tokenAddress, uint id, uint price, uint quantity, uint filled, string tradeType, string tradeHash, address tradeAddress);

    TRC20 private TRC20Interface;

    constructor() public {
        adminAddress = msg.sender;
    }

    function updateAdmin(address newAddress) public {
        require(msg.sender == adminAddress);
        adminAddress = newAddress;
    }
    
    function buyOrder(address tokenAddress, uint buyPrice, uint quantity, string tradeHash) payable public returns (uint) {
        require(buyPrice * quantity >= 100000); //Prices are in 10**5, so this hack code takes care of that
        require(msg.value * 10**5 >= buyPrice * quantity);

        buyOrders[tokenAddress][buyPrice].push(tradeStruct(
            msg.sender, //address
            quantity, //quantity
            0, //filled
            tradeHash
        ));
        
        uint filled = 0;
        uint buyOrderId = buyOrders[tokenAddress][buyPrice].length - 1; //the id of the buyOrder mapping array
        
        for (uint i = 0; i < sellOrders[tokenAddress][buyPrice].length; i++) {
            tradeStruct storage sellOrderVar = sellOrders[tokenAddress][buyPrice][i];
            
            if (sellOrderVar.filled < sellOrderVar.quantity && filled < quantity) {
                if (sellOrderVar.quantity - sellOrderVar.filled >= quantity - filled && filled < quantity) {
                    sellOrderVar.filled += quantity - filled;
                    filled += quantity - filled;
                    //emit FillOrder(tokenAddress, i, sellOrderVar.filled, "sell", sellOrderVar.tradeAddress);
                    
                } else if (sellOrderVar.quantity - sellOrderVar.filled < quantity - filled && filled < quantity) {
                    filled += sellOrderVar.quantity - sellOrderVar.filled;
                    sellOrderVar.filled += sellOrderVar.quantity - sellOrderVar.filled;
                    //emit FillOrder(tokenAddress, buyOrderId, filled, "buy", msg.sender);
                }

                sellOrders[tokenAddress][buyPrice][i].filled = sellOrderVar.filled; //set the sellorder filled to the local copy
                buyOrders[tokenAddress][buyPrice][buyOrderId].filled = filled; //set the buyorders mapping filled to filled

                if (filled >= quantity) {
                    fillBuyOrder(buyOrderId, tokenAddress, buyPrice); //fill the buy order
                }

                if (sellOrderVar.filled >= sellOrderVar.quantity) {
                    fillSellOrder(i, tokenAddress, buyPrice); //fill the sell order
                    i--; //required because otherwise we will get an arrayOutOfBoundsExceptopn
                }
            }
        }
        
        emit buyOrderEvent(tokenAddress, buyOrderId, buyPrice, quantity, filled, "buy", tradeHash, msg.sender);
        return buyOrderId;
    }
    
   function sellOrder(address tokenAddress, uint sellPrice, uint quantity, string tradeHash) public returns (uint) {
        require(sellPrice * quantity >= 100000); //Make sure the user is selling at least 1 TRX worth (prices are in 10**5)
        require(TRC20(tokenAddress).allowance(msg.sender, address(this)) >= quantity);
        
        TRC20(tokenAddress).transferFrom(msg.sender, address(this), quantity); //attempt to transfer tokens

        sellOrders[tokenAddress][sellPrice].push(tradeStruct(
            msg.sender, //address
            quantity, //quantity
            0, //filled
            tradeHash
        ));
        
        uint filled = 0;
        uint sellOrderId = sellOrders[tokenAddress][sellPrice].length - 1; //the id of the sellOrder mapping array
        
        for (uint i = 0; i <  buyOrders[tokenAddress][sellPrice].length; i++) {
            tradeStruct storage buyOrderVar = buyOrders[tokenAddress][sellPrice][i];
          
            if (buyOrderVar.filled < buyOrderVar.quantity && filled < quantity) {
                if (buyOrderVar.quantity - buyOrderVar.filled >= quantity - filled && filled < quantity) {
                    buyOrderVar.filled += quantity - filled;
                    filled += quantity - filled;
                } else if (buyOrderVar.quantity - buyOrderVar.filled < quantity - filled && filled < quantity) {
                    filled += buyOrderVar.quantity - buyOrderVar.filled;
                    buyOrderVar.filled += buyOrderVar.quantity - buyOrderVar.filled;
                }

                buyOrders[tokenAddress][sellPrice][i].filled = buyOrderVar.filled; //set the sellorder filled to the local copy
                sellOrders[tokenAddress][sellPrice][sellOrderId].filled = filled; //set the buyorders mapping filled to filled

                if (filled >= quantity) {
                    fillSellOrder(sellOrderId, tokenAddress, sellPrice); //fill the sell order
                }

                if (buyOrderVar.filled >= buyOrderVar.quantity) {
                    fillBuyOrder(i, tokenAddress, sellPrice); //fill the buy order
                    i--; //required because otherwise we will get an arrayOutOfBoundsExceptopn
                }
            }
        }
      
        emit sellOrderEvent(tokenAddress, sellOrderId, sellPrice, quantity, filled, "sell", tradeHash, msg.sender);
        return sellOrderId;
    }
    
    function cancelBuyOrder(uint id, address tokenAddress, uint buyPrice) public {
        require(buyOrders[tokenAddress][buyPrice][id].tradeAddress == msg.sender);
        fillBuyOrder(id, tokenAddress, buyPrice);
    }
    
    function cancelSellOrder(uint id, address tokenAddress, uint sellPrice) public {
        require(sellOrders[tokenAddress][sellPrice][id].tradeAddress == msg.sender);        
        fillSellOrder(id, tokenAddress, sellPrice);
    }
    
    function fillBuyOrder(uint id, address tokenAddress, uint buyPrice) private returns (bool) {
        tradeStruct storage buyOrderVar = buyOrders[tokenAddress][buyPrice][id];
        uint quantity = buyOrderVar.quantity;
        uint filled = buyOrderVar.filled;
        address tradeAddress = buyOrderVar.tradeAddress;
        string hashVar = buyOrderVar.tradeHash;

        if (buyOrderVar.filled < buyOrderVar.quantity) {
          buyOrderVar.tradeAddress.transfer((buyOrderVar.quantity - buyOrderVar.filled) * buyPrice * 10); //if the whole order hasn't been filled, transfer the remaining TRX
        }
        
        if (buyOrderVar.filled > 0) {
          TRC20(tokenAddress).transfer(buyOrderVar.tradeAddress, buyOrderVar.filled);
        }

        if (buyOrderVar.filled > 0) {
            emit CompleteTrade(tokenAddress, id, buyPrice, quantity, filled, "buy", buyOrders[tokenAddress][buyPrice][id].tradeHash, tradeAddress);
        }

        if (buyOrders[tokenAddress][buyPrice].length > 1) {
            buyOrders[tokenAddress][buyPrice][id] = buyOrders[tokenAddress][buyPrice][buyOrders[tokenAddress][buyPrice].length - 1]; //replace the current array item with the last item in the array
            buyOrders[tokenAddress][buyPrice].length--; //remove the last item from the buyorders array
        } else {
            delete(buyOrders[tokenAddress][buyPrice]); //if there aren't any items, delete the whole array
        }

        return true;
    }
    
    function fillSellOrder(uint id, address tokenAddress, uint sellPrice) private returns (bool) {       
        tradeStruct storage sellOrderVar = sellOrders[tokenAddress][sellPrice][id];
        uint quantity = sellOrderVar.quantity;
        uint filled = sellOrderVar.filled;
        address tradeAddress = sellOrderVar.tradeAddress;
        //string hashVar = sellOrderVar.tradeHash;

        if (sellOrderVar.filled < sellOrderVar.quantity) {
          TRC20(tokenAddress).transfer(sellOrderVar.tradeAddress, sellOrderVar.quantity - sellOrderVar.filled);
        }

        if (sellOrderVar.filled > 0) {
          tradeAddress.transfer(sellOrderVar.filled * sellPrice * 10);
        }

        if (sellOrderVar.filled > 0) {
            emit CompleteTrade(tokenAddress, id, sellPrice, quantity, filled, "sell", sellOrders[tokenAddress][sellPrice][id].tradeHash, tradeAddress);
        }

        if (sellOrders[tokenAddress][sellPrice].length > 1) {
            sellOrders[tokenAddress][sellPrice][id] = sellOrders[tokenAddress][sellPrice][sellOrders[tokenAddress][sellPrice].length - 1]; //replace the current array item with the last item in the array
            sellOrders[tokenAddress][sellPrice].length--; //remove the last item from the buyorders array
        } else {
            delete(sellOrders[tokenAddress][sellPrice]); //if there aren't any items, delete the whole array
        }

        return true;
    }
}