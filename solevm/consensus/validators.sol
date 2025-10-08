pragma solidity ^0.8.1;

contract ManageValidators {

    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    address[] public validators;
    
    function addValidator(address _addy) public {
        if (msg.sender == owner) {
            validators.push(_addy);
        }
    }
    
    function validatorCount() public view returns (uint) {
        return validators.length;
    }
    
    function getValidators()public view returns( address  [] memory){
        return validators;
    }
}
