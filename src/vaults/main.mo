import Types "types";
import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Hash "mo:base/Hash";
import CkBtcLedger "canister:ckbtc_ledger";
import { init_position_figures ; toAccount; toSubaccount } "helpers";
import Error "mo:base/Error";

actor Vaults {

  var oracle = actor("be2us-64aaa-aaaaa-qaabq-cai") : Types.oracle;

  stable var ckbtcRate : Nat = 0;
  let liquidationRate : Nat = 135;
  var irscRate = 8225;
  var stabilityFee = 1;
  var liquidationFee = 5;

  var open_cdps = HashMap.HashMap<Principal, Types.CDP>(5, Principal.equal, Principal.hash);


  public query func getckBTCRate() : async Nat {
    ckbtcRate;
  };

  public shared ({ caller }) func create_cdp( _debtrate : Nat, _amount : Nat ) : async Result.Result<Types.CDP, Text> {
    
    // Check for an already open position.
    switch (open_cdps.get(caller)) {
      case null { 

        let balance = await CkBtcLedger.icrc1_balance_of(
          toAccount({ caller; canister = Principal.fromActor(Vaults) })
        );

        if (balance < _amount) {
          return #err("Not enough funds available in the Account. Make sure you send required ckBTC");
        };

        var btc_rate = await oracle.getBTC();
        
        Result.assertOk(btc_rate);
        let result_val = Result.toOption(btc_rate);
        switch(result_val) {
          case null { return #err("Something is wrong with the Oracle") };
          case (?num) {

            ckbtcRate := num;

            try {
              // if enough funds were sent, move them to the canisters default account
              let transferResult = await CkBtcLedger.icrc1_transfer(
                {
                  amount = _amount;
                  from_subaccount = ?toSubaccount(caller);
                  created_at_time = null;
                  fee = null;
                  memo = null;
                  to = {
                    owner = Principal.fromActor(Vaults);
                    subaccount = null;
                  };
                }
              );

              switch (transferResult) {
                case (#Err(transferError)) {
                  return #err("Couldn't transfer funds to default account:\n" # debug_show (transferError));
                };
                case (_) {};
              };
            } catch (error : Error) {
              return #err("Reject message: " # Error.message(error));
            };

            let calc = init_position_figures(liquidationRate + _debtrate, num, _amount);

            let new_pos : Types.CDP = {
              debtor = caller;
              amount = _amount;
              debt_rate = liquidationRate + _debtrate;
              entry_rate = num;
              liquidation_rate = calc.liquidation_rate;
              max_debt = calc.max_debt;
              debt_issued = 0;
              state = #active
            };

            open_cdps.put(caller, new_pos);
            return #ok(new_pos);
          }
        }
       };
      case (?pos) {
        return #err("You already have an open position!");
      }
    }
  };

  public shared ({ caller }) func get_current_cdp() : async ?Types.CDP {
    open_cdps.get(caller);
  };

  public shared ({ caller }) func get_subAccount() : async Types.Account {
    toAccount({ caller; canister = Principal.fromActor(Vaults) });
  };

};
