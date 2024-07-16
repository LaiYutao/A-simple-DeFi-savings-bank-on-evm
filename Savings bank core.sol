// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

//判断管理员权限；
contract Ownable{
    address public owner;

    constructor () {
        owner = msg.sender;
    }

    modifier onlyOwner{
        require (msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner{
        if(newOwner != address(0)){
            owner = newOwner;
        }
    }
}

//暂停功能
contract Pausable is Ownable{
    event Pause(uint256);
    event Unpause(uint256);

    bool public paused = false;

    modifier whenNotPaused{
        require(!paused);
        _;
    }

    modifier whenPaused{
        require(paused);
        _;
    }

    function pause() onlyOwner whenNotPaused public {
        paused = true;
        emit Pause(block.timestamp);
    }

    function unpause() onlyOwner whenPaused public {
        paused = false;
        emit Unpause(block.timestamp);
    }
    
}

//黑名单功能
contract BlackList is Ownable{
    mapping (address => bool) public isBlackListed;
    event AddedBlackList(address _user);
    event RemovedBlackList(address _user);

    function getOwner() external view returns(address){
        return owner;
    }

    function getBlackListStatus(address _customer) external view returns(bool){
        return isBlackListed[_customer];
    }

    function addBlackList (address _evilUser) public onlyOwner{
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    function removeBlackList (address _clearedUser) public onlyOwner{
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }

    modifier onlyValid{
        require(!isBlackListed[msg.sender]);
        _;
    }
}

//存款系统主要部分
contract SavingSystem is Pausable, BlackList{

    constructor() payable {
        showType[DepositType.Demand]="Demand deposit";
        showType[DepositType.HalfYear]="Half year deposit";
        showType[DepositType.OneYear]="One year deposit";
    }
    
    enum DepositType{Demand, HalfYear, OneYear}
    uint public DmDemandDepositInterestRate = 50; // 活期利率； 万分之一计；
    uint public DmHalfYearDepositInterestRate = 200; //半年利率；万分之一计；
    uint public DmOneYearDepositInterestRate = 250; //一年利率；万分之一计；

    event changeDepositInterestRate(string depositType,uint from ,uint to);

    function changeDemandDepositInterestRate(uint _newInterestRate) external onlyOwner {  //更改活期利率
        emit changeDepositInterestRate("DmDemandDepositInterestRate",DmDemandDepositInterestRate,_newInterestRate);
        DmDemandDepositInterestRate = _newInterestRate;
    }

        function changeHalfYearDepositInterestRate(uint _newInterestRate) external onlyOwner{  //更改半年利率
        emit changeDepositInterestRate("DmHalfYearDepositInterestRate",DmHalfYearDepositInterestRate,_newInterestRate);
        DmHalfYearDepositInterestRate = _newInterestRate;
    }

     function changeOneYearDepositInterestRate(uint _newInterestRate) external onlyOwner{  //更改半年利率
        emit changeDepositInterestRate("DmOneYearDepositInterestRate",DmOneYearDepositInterestRate,_newInterestRate);
        DmOneYearDepositInterestRate = _newInterestRate;
    }
    
    //mapping
    mapping (address=>mapping(uint=>certificate)) checking; //先地址再序号，定位存单
    mapping (address=>mapping(uint=>uint)) corrective; //取款后，删除存单，需要进行编号重定位；就不用多次复制其他序号的结构体了 
    mapping (address=>number) getNumber; //获取number结构体
    mapping (DepositType=>string) showType;



    //存单结构体
    struct certificate{
        DepositType depositType;
        uint amount;
        uint saveTime; //存款时间（不是时长）；
    }

    //“数量”结构体
    struct number{
        uint currentNumber;
        uint historyNumber;  //历史存单继续往后；和当前存单的差值就是新存单的偏移量
    }

    //事件
    event Received(address sender,uint value,uint time);
    event madeDemandDeposit(address customer,uint value,uint time);
    event madeHalfYearDeposit(address customer,uint value,uint time);
    event madeOneYearDeposit(address customer,uint value,uint time);
    event tookMoney(address customer,string depositType, uint value,uint timeOfSaving,uint timeOfTaking);
    event tookMoneyTooEarly(string);

    receive() external payable { 
        emit Received(msg.sender,msg.value,block.timestamp);
    }

    //存单函数
    function deposit(DepositType _depositType) internal {
        getNumber[msg.sender].currentNumber++;
        getNumber[msg.sender].historyNumber++;
        checking[msg.sender][getNumber[msg.sender].historyNumber] = certificate(_depositType,msg.value,block.timestamp);
        corrective[msg.sender][getNumber[msg.sender].currentNumber]=getNumber[msg.sender].historyNumber; //重连接(尾部接尾部)；
    }

    //选择存款类型；(多套一个函数壳是为了多几个按钮，而不是输参数)
    function makeDemandDeposit() public whenNotPaused onlyValid payable { 
       deposit(DepositType.Demand);
        emit madeDemandDeposit(msg.sender,msg.value,block.timestamp);
    }

    function makeHalfYearDeposit() public whenNotPaused onlyValid payable{
       deposit(DepositType.HalfYear);
        emit madeHalfYearDeposit(msg.sender,msg.value,block.timestamp);
    }

    function makeOneYearDeposit() public whenNotPaused onlyValid payable{
        deposit(DepositType.OneYear);
        emit madeOneYearDeposit(msg.sender,msg.value,block.timestamp);
    }    
   
    //返回顾客存单数量，用于后续查询；
    function getNumberOfCertificate() external view returns(uint) {  
        return getNumber[msg.sender].currentNumber;
    }

    //根据序号查询订单消息；
    function getCertificateInformation(uint _order) external view returns(string memory depositType, uint amount, uint saveTime){ 
        uint aimedOrder = corrective[msg.sender][_order];
        return(showType[checking[msg.sender][aimedOrder].depositType],checking[msg.sender][aimedOrder].amount,checking[msg.sender][aimedOrder].saveTime);
    }

    //取钱后的再排序步骤
    function reset(uint _order,uint aimedOrder)internal{
        for(uint i=0;i<getNumber[msg.sender].currentNumber-_order;++i){ 
                corrective[msg.sender][_order + i] = aimedOrder + i + 1; //往右偏一位；
            }
            getNumber[msg.sender].currentNumber--; //现存存单数量减一。
    }

    //取钱
    function takeMoney(uint _order) external whenNotPaused onlyValid payable{
        uint aimedOrder = corrective[msg.sender][_order]; //对应到历史存单
       
        if(checking[msg.sender][aimedOrder].depositType == DepositType.Demand){
            uint duration = (block.timestamp - checking[msg.sender][aimedOrder].saveTime)/84600; //单位为天
            uint calculatedAmount = checking[msg.sender][aimedOrder].amount + duration * DmDemandDepositInterestRate/10000/365 * checking[msg.sender][aimedOrder].amount;
            payable(msg.sender).transfer(calculatedAmount);
            emit tookMoney(msg.sender,"Demand deposit",calculatedAmount,checking[msg.sender][aimedOrder].saveTime,block.timestamp);
            
            //再排序
            reset(_order,aimedOrder);
        }
        else if(checking[msg.sender][aimedOrder].depositType == DepositType.HalfYear){
            uint duration = (block.timestamp - checking[msg.sender][aimedOrder].saveTime)/84600;
            if( duration >=182 ){ //182是半年,超出时间的转为活期。
                uint calculatedAmount = checking[msg.sender][aimedOrder].amount + 182 * DmHalfYearDepositInterestRate/10000/365 * checking[msg.sender][aimedOrder].amount + (duration - 182)*DmDemandDepositInterestRate/10000/365*checking[msg.sender][aimedOrder].amount;
                payable(msg.sender).transfer(calculatedAmount);
                emit tookMoney(msg.sender,"Half year deposit",calculatedAmount,checking[msg.sender][aimedOrder].saveTime,block.timestamp);
            }
            else{
                uint calculatedAmount = checking[msg.sender][aimedOrder].amount;
                payable(msg.sender).transfer(calculatedAmount);
                emit tookMoney(msg.sender,"Half year deposit",calculatedAmount,checking[msg.sender][aimedOrder].saveTime,block.timestamp);
                emit tookMoneyTooEarly("Took money too early. No interest."); //提前取款，没有利息，只能去取出本金。
            }
            //再排序
            reset(_order,aimedOrder);
        }
        else if(checking[msg.sender][aimedOrder].depositType == DepositType.OneYear){
            uint duration = (block.timestamp - checking[msg.sender][aimedOrder].saveTime)/84600;
             if( duration >=365 ){ 
                uint calculatedAmount = checking[msg.sender][aimedOrder].amount +  DmOneYearDepositInterestRate/10000 * checking[msg.sender][aimedOrder].amount + (duration -365)*DmDemandDepositInterestRate/10000/365*checking[msg.sender][aimedOrder].amount;
                payable(msg.sender).transfer(calculatedAmount);
                emit tookMoney(msg.sender,"One year deposit",calculatedAmount,checking[msg.sender][aimedOrder].saveTime,block.timestamp);
            }
            else{
                uint calculatedAmount = checking[msg.sender][aimedOrder].amount;
                payable(msg.sender).transfer(calculatedAmount);
                emit tookMoney(msg.sender,"One year deposit",calculatedAmount,checking[msg.sender][aimedOrder].saveTime,block.timestamp);
                emit tookMoneyTooEarly("Took money too early. No interest."); //提前取款，没有利息，只能去取出本金。
            }
             //再排序
            reset(_order,aimedOrder);
        }
    }
}