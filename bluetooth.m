//
//  bluetooth.m
//  blueToothInterface
//
//  Created by ChenHong on 2018/3/6.
//  Copyright © 2018年 macro-c. All rights reserved.
//

#import "bluetooth.h"


@interface DDBluetooth()

/*
 central端使用属性
 **/

@property (nonatomic, strong) CBCentralManager *centralManager;
// central可用状态（程序未使用）
@property (nonatomic, assign) BOOL centralAvailable;
// 扫描计数器
@property (nonatomic, strong) NSTimer *scanDeviceTimer;
// 扫描次数，定时清理设备列表
@property (nonatomic, assign) NSInteger scanTimes;
// 保存收听的peripherals
@property (nonatomic, strong) NSMutableArray<CBPeripheral *> *peripheralsFollow;
// 当前central所监听的特征
@property (nonatomic, strong) CBCharacteristic *characteristicFollow;
// 暂存当前正在遍历服务和特征值的 CBPeripheral实例，
// 此实例需要暂存，否则很可能使此次连接失效
@property (nonatomic, strong) CBPeripheral *peripheralToHandle;


/*
 peripheral端使用属性
 **/
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
// 保存被收听的centrals
@property (nonatomic, strong) NSMutableArray<CBCentral *> *centralsFollow;
// 保存每个central对应消息最长值，为NSNumber类型
@property (nonatomic, strong) NSMutableArray *centralsMaxMessageLength;
// 当前外设的服务和特征
@property (nonatomic, strong) CBMutableCharacteristic *characteristicForAdv;
@property (nonatomic, strong) CBMutableService *service;
@property (nonatomic, strong) NSString *serviceUUID;
@property (nonatomic, strong) NSString *characterUUID;
// 自定义用户名，手动筛选
@property (nonatomic, strong) NSString *userName;
// 暂存更新的特征值
@property (nonatomic, strong) NSData *tempCharacteristicValue;


/*
 公共属性
 **/
// 蓝牙授权状态
@property (nonatomic, assign) BOOL appAuthorizedStatus;
// 针对应用间安全验证--思路：对方随机产生一个数字，在appUUID中作为索引找到相应字符,返回验证（双向）
@property (nonatomic, strong) NSString *appUUID;
// 用户名，固定，central连接时首先筛选name
@property (nonatomic, strong) NSString *userNamePrifix;
// 固定消息，表示peripheral端主动关闭
@property (nonatomic, strong) NSString *peripheralStopChatMessage;
// 角色信息，连接中当前一方的角色 true表示peripheral，false表示central
@property (nonatomic, strong) NSString *chatRole;

// 标识已经主动关闭（被自己或对方），为YES则忽略之后的被动关闭回调
// initiative主动的
@property (nonatomic, assign) BOOL closeInitiative;

@end




@implementation DDBluetooth

- (void) initProperties {
    
    // 初始化UUID
    self.serviceUUID = @"68753A44-4D6F-1226-9C60-0050E4C00067";
    self.characterUUID = @"68753A44-4D6F-1226-9C60-0050E4C00068";
    // 自动连接模式使用（用于身份验证），手动连接不需要
    self.appUUID = @"68753A44-1222-1226-9C60-0050E4C00068";
    
    self.centralAvailable = NO;
    self.appAuthorizedStatus = NO;
    self.deviceArray = [[NSMutableArray alloc] init];
    self.userNamePrifix = @"name666";
    
    // 外设支持的服务，以及特征值
    self.service = [[CBMutableService alloc] initWithType:[CBUUID UUIDWithString:self.serviceUUID] primary:YES];
    self.characteristicForAdv = [[CBMutableCharacteristic alloc] initWithType:[CBUUID UUIDWithString:self.characterUUID] properties:CBCharacteristicPropertyNotify | CBCharacteristicPropertyWrite value:nil permissions:CBAttributePermissionsReadable | CBAttributePermissionsWriteable];//属性设为通知
    [self.service setCharacteristics: @[self.characteristicForAdv]];

    self.peripheralStopChatMessage = @"双击666拜拜";
    self.chatRole = @"";
    
    self.centralsFollow = [[NSMutableArray alloc] init];
    self.peripheralsFollow = [[NSMutableArray alloc] init];
    self.centralsMaxMessageLength = [[NSMutableArray alloc] init];
    // 默认被动关闭
    self.closeInitiative = NO;
    
    self.tempCharacteristicValue = [[NSData alloc] init];
}

- (void) releaseProperties {
    
    if(self.characteristicFollow) {
        self.characteristicFollow = nil;
    }
    if(self.centralsFollow.count != 0) {
        [self.centralsFollow removeAllObjects];
    }
    if(self.centralsMaxMessageLength.count != 0) {
        [self.centralsMaxMessageLength removeAllObjects];
    }
    if(self.peripheralsFollow.count != 0) {
        [self.peripheralsFollow removeAllObjects];
    }
    if(self.scanDeviceTimer) {
        [self.scanDeviceTimer invalidate];
        self.scanDeviceTimer = nil;
    }
    if(self.chatRole) {
         self.chatRole = @"";
    }
    if(self.deviceArray.count != 0) {
        [self.deviceArray removeAllObjects];
        if([self.unNamedDelegate respondsToSelector:@selector(deviceArrayIsChanged)]) {
            
            [self.unNamedDelegate deviceArrayIsChanged];
        }
    }
    if(self.userName) {
        self.userName = @"";
    }
    self.closeInitiative = NO;
}

- (instancetype) initWithDelegate:(id<DDBluetoothDelegate>)delegate {
    
    self = [super init];
    self.unNamedDelegate = delegate;
    
    [self initProperties];
    
    return self;
}

- (void)setDelegate:(id<DDBluetoothDelegate>)delegate {
    
    self.unNamedDelegate = delegate;
}

- (void)startWorkingWithAdvName:(NSString *)name {
    
    // 代理必须设置
    if(!self.unNamedDelegate) {
        NSLog(@"代理对象不能空！");
    }
    assert(self.unNamedDelegate);
    
    // central端开始扫描
    self.scanDeviceTimer = [NSTimer timerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(searchDevice)
                                                     userInfo:nil
                                                      repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.scanDeviceTimer forMode:NSRunLoopCommonModes];
    
    // peripheral端初始化，确定蓝牙可用（代理方法中）后开始广播
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    if(!self.deviceArray) {
        self.deviceArray = [[NSMutableArray alloc] init];
    }
    self.userName = name;
}

- (void) sendMessageToPeer:(NSString *)message {
    
    //外设端
    if([self.chatRole isEqualToString:@"peripheral"]) {
        [self sendMessageFromPeripheral:message];
    }
    else {
        [self sendMessageFromCentral:message];
    }
}


// 主动关闭 (不走任何可能混淆被动关闭的方式，如取消订阅)
- (void) shutDownConnection {
    
    if(self.peripheralsFollow.count != 0 && [self.chatRole isEqualToString:@"central"]) {
        
        [self sendMessageToPeer:self.peripheralStopChatMessage];
        [self.centralManager stopScan];
        [self releaseProperties];
    }
    
    if(self.centralsFollow.count != 0 && [self.chatRole isEqualToString:@"peripheral"]) {
        
        // peripheral端无法以接口关闭连接，并让对方感知；所以发送 peripheralStopChatMessage 消息，表示外设端已关闭
        
        [self sendMessageToPeer:self.peripheralStopChatMessage];
        [self releaseProperties];
    }
    
    // 置空聊天角色
    self.chatRole = @"";
}

// 连接某个设备
// arg--设备数组中索引值
- (void) connectDeviceAtIndex:(NSInteger)index {
    
    NSInteger deviceCount = self.deviceArray.count;
    if(index >(deviceCount-1)) {
        
        return;
    }
    
    CBPeripheral *peripheralToConnect = [self.deviceArray[index] objectForKey:@"peripheral"];
    if(!peripheralToConnect) {
        return;
    }
    // option表示 外设断开连接时central收到通知，系统级别通知，会将程序挂起，不需要应用有消息权限
    // 以及 CBConnectPeripheralOptionNotifyOnNotificationKey 等key值
    // 所以 此framework采用取消订阅实现发送central下线通知
    [self.centralManager connectPeripheral:peripheralToConnect
                                   options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey:@(YES),
                                             CBConnectPeripheralOptionNotifyOnNotificationKey:@(YES)
                                             }];
    // 以下key为YES时，当程序位于后台，且收到订阅消息时，会收到系统级提示
    // ,CBConnectPeripheralOptionNotifyOnNotificationKey:@(YES)
    NSLog(@"开始连接设备");
}

- (void) connectDevice {
    
    [self connectDeviceAtIndex:0];
    NSLog(@"connectDevice click and run");
}


#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    
    NSLog(@" our center is %@",central);
    switch (central.state) {
        case CBManagerStatePoweredOn:
            
            NSLog(@"蓝牙当前可用");
            self.centralAvailable = YES;
            self.appAuthorizedStatus = YES;
            break;
        case CBManagerStatePoweredOff:
        {
            self.centralAvailable = NO;
            NSLog(@"蓝牙未打开");
            if([self.unNamedDelegate respondsToSelector:@selector(bluetoothUnAvailable)]) {
                
                [self.unNamedDelegate bluetoothUnAvailable];
            }
            break;
        }
        case CBManagerStateUnsupported:
            NSLog(@"SDK不支持");
            self.centralAvailable = NO;
            break;
        case CBManagerStateUnauthorized:
            NSLog(@"程序未授权");
            self.centralAvailable = NO;
            self.appAuthorizedStatus = NO;
            [self bluetoothUnAuthorized];
            break;
        case CBManagerStateResetting:
            NSLog(@"正在重置");
            self.centralAvailable = NO;
            break;
        case CBManagerStateUnknown:
            NSLog(@"未知状态");
            self.centralAvailable = NO;
            break;
        default:
            break;
    }
}


- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    
    // 当前外设设备名称,区别于 advertisementData中的名称,一般合法名称为iphone
    if (peripheral.name.length <= 0) {
        return ;
    }
    
    // 解析广播内容中的名称
    NSString *peripheralName = [advertisementData valueForKey:CBAdvertisementDataLocalNameKey];
    if(![peripheralName hasPrefix:self.userNamePrifix])
    {
        return;
    }
    else {
    }
    
    // 根据RSSI计算距离
    NSInteger rssi = abs([RSSI intValue]);
    CGFloat ci = (rssi - 49) / (10 * 4.);
    CGFloat distance = pow(10, ci);
    NSString *dis = [NSString stringWithFormat:@"%0.1f",distance];
    
    // 保存扫描到的设备信息
    NSDictionary *dict = @{@"peripheral":peripheral, @"RSSI":RSSI,@"peripheralName":peripheralName,@"deviceDistance":dis};
    
    // 向deviceArray 中添加或更新设备
    if (self.deviceArray.count == 0) {
        
        [self.deviceArray addObject:dict];
        if([self.unNamedDelegate respondsToSelector:@selector(deviceArrayIsChanged)]) {
            
            [self.unNamedDelegate deviceArrayIsChanged];
        }
    } else {
        BOOL isExist = NO;
        for (int i = 0; i < self.deviceArray.count; i++) {
            NSDictionary *dict = [self.deviceArray objectAtIndex:i];
            CBPeripheral *per = dict[@"peripheral"];
            if ([per.identifier.UUIDString isEqualToString:peripheral.identifier.UUIDString]) {
                isExist = YES;
                NSString *peripheralNameExist = [advertisementData valueForKey:CBAdvertisementDataLocalNameKey];
                if(!peripheralNameExist) {
                    peripheralNameExist = @"";
                }
                NSDictionary *dict = @{@"peripheral":peripheral, @"RSSI":RSSI,@"peripheralName":peripheralNameExist,@"deviceDistance":dis};
                [_deviceArray replaceObjectAtIndex:i withObject:dict];
            }
        }
        if( !isExist ) {
            [self.deviceArray addObject:dict];
            if([self.unNamedDelegate respondsToSelector:@selector(deviceArrayIsChanged)]) {
                
                [self.unNamedDelegate deviceArrayIsChanged];
            }
        }
    }
    
    // 回调搜索到目标
    if([self.unNamedDelegate respondsToSelector:@selector(deviceIsReadyToConnect)]) {
        [self.unNamedDelegate deviceIsReadyToConnect];
    }
    
    [self sortDeviceArray];
}


- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    
    NSLog(@"连接设备失败：");
    NSLog(@"%@",error);
}


- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    
    NSLog(@" 连接设备成功 ");
    
    // 为降低硬件消耗，停止扫描设备;进行服务、特征值筛选。
    [self.scanDeviceTimer invalidate];
    self.scanDeviceTimer = nil;
    [self.centralManager stopScan];
    
    // 暂存外设，否则在连接建立前释放的话，此次连接将无效。所以需要持有
    self.peripheralToHandle = peripheral;
    // 查找服务
    [peripheral discoverServices:nil];
    peripheral.delegate = self;
}

// 外设通过关闭蓝牙，或者超出连接距离而断开（app连接被动断开）
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(nullable NSError *)error {
    
    if(error)
    {
        NSLog(@"断开连接的原因是%@",error);
    }
    
    // 当前并未主动关闭
    if([self.unNamedDelegate respondsToSelector:@selector(shutDownByBlueTooth)] && !self.closeInitiative) {
        
        [self.unNamedDelegate shutDownByBlueTooth];
    }
    
    [self connectionRelease];
}


#pragma mark - CBPeripheralDelegate

/*
 查找peripheral服务
 **/
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(nullable NSError *)error {
    
    if (error) {
        NSLog(@"出错了%@",error);
        return;
    }
    
    NSString *UUID = [peripheral.identifier UUIDString];
    CBUUID *cbUUID = [CBUUID UUIDWithString:UUID];
    NSLog(@"外设的CBUUID--:%@",cbUUID);
    
    for (CBService *service in peripheral.services) {
        
        NSLog(@"service:%@",service.UUID);
        if([service.UUID isEqual:[CBUUID UUIDWithString: @"68753A44-4D6F-1226-9C60-0050E4C00067"]])
        {
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}

/*
 监听符合的特征值
 **/
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(nullable NSError *)error {
    
    if(error)
    {
        NSLog(@"出错了%@",error);
        return;
    }
    for (CBCharacteristic *character in service.characteristics) {
        
        if([character.UUID isEqual:[CBUUID UUIDWithString: @"68753A44-4D6F-1226-9C60-0050E4C00068"]])
        {
            
            [peripheral setNotifyValue:YES forCharacteristic:character];
            
            // 至此，当前连接完成
            // 设置连接的角色
            self.chatRole = @"central";
            [self.peripheralsFollow addObject: peripheral];
            self.characteristicFollow = character;
            
            if([self.unNamedDelegate respondsToSelector:@selector(connectionIsOk)]) {
                
                [self.unNamedDelegate connectionIsOk];
            }
            return;
        }
        
        CBCharacteristicProperties property = character.properties;
        if(property & CBCharacteristicPropertyBroadcast)
        {
            // 广播特征
        }
        if(property & CBCharacteristicPropertyRead) {
            
        }
        if(property & CBCharacteristicPropertyWriteWithoutResponse) {
            
            // 表示当前服务的特征允许写入数据
        }
        if(property & CBCharacteristicPropertyWrite) {
            
            // 当前特征可写，且写入之后，需要对方回复--当前外设的属性是可读且需要回复，则写入数据之后，超时10秒等待外设做出回应
            // 否则didWriteValueForCharacteristic，状态为未知错误
        }
        if(property & CBCharacteristicPropertyNotify) {
            
        }
        if(property & CBCharacteristicPropertyIndicate) {
            
        }
        if(property & CBCharacteristicPropertyAuthenticatedSignedWrites) {
            
        }
        if(property & CBCharacteristicPropertyExtendedProperties) {
            
        }
        if(property & CBCharacteristicPropertyNotifyEncryptionRequired) {
            
        }
        if(property & CBCharacteristicPropertyIndicateEncryptionRequired) {
            
        }
    }
}
/*
 central端收到的数据
 peripheral主动关闭连接
 **/
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    if(error) {
        
        return;
    }
    
    NSData *data = characteristic.value;
    if (data.length <= 0) {
        NSLog(@"接收到不合法数据");
        return;
    }
    
    // 读取特征中携带的数据
    NSString *info = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    // 对方主动关闭连接
    if([info isEqualToString:self.peripheralStopChatMessage]) {
        if([self.unNamedDelegate respondsToSelector:@selector(shutDownByPeer)]) {
            
            [self.unNamedDelegate shutDownByPeer];
        }
        self.closeInitiative = YES;
        [self connectionRelease];
        
        NSLog(@"central端被主动关闭");
        return;
    }
    if([self.unNamedDelegate respondsToSelector:@selector(recvMessage:)]) {
        
        [self.unNamedDelegate recvMessage:info];
    }
}

/*
 central端写入数据成功 / 失败
 **/
- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    // 如果 writeValue方法 的type参数是withresponse 但接收方（外设）并没有respondToRequest，超时10秒，出现错误
    // 为保证尽量高的传输安全  需要在这里动手脚
    if(error)
    {

        NSLog(@"error is ..%@",error);
        return;
    }
}

/*
 信号强度更新
 **/
- (void)peripheralDidUpdateRSSI:(CBPeripheral *)peripheral error:(nullable NSError *)error {
    
    
}


#pragma mark - CBPeripheralManagerDelegate

// 初始化 peripheralManager变量时调用，判断状态后peripheralmanager初始化
- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    
    /**
     CBManagerStateUnknown = 0,
     CBManagerStateResetting,
     CBManagerStateUnsupported,
     CBManagerStateUnauthorized,
     CBManagerStatePoweredOff,
     CBManagerStatePoweredOn,
     */
    if (@available(iOS 10.0, *)) {
        
    }
    else
    {
        //呵呵
        NSLog(@"需要IOS 10以上，亲");
        return;
    }
    
    // 广播名称
    NSString *advNameFull = [self.userNamePrifix stringByAppendingString:self.userName];
    
    switch (peripheral.state) {
        case CBManagerStatePoweredOff:
            
            NSLog(@" 蓝牙关闭 ");
            if([self.unNamedDelegate respondsToSelector:@selector(bluetoothUnAvailable)]) {
                
                [self.unNamedDelegate bluetoothUnAvailable];
            }
            break;
        case CBManagerStatePoweredOn:
            
            NSLog(@" 蓝牙状态正常 ");
            [self.peripheralManager removeAllServices];
            // 添加service
            [self.peripheralManager addService:self.service];
            // 开始广播
            [self.peripheralManager startAdvertising:@{CBAdvertisementDataLocalNameKey:advNameFull}];
            break;
            
        case CBManagerStateUnauthorized:
            
            // 未授权，在central端会判断，并调用未授权代理方法，这里不重复调用
            break;
            
        case CBManagerStateResetting:
            
            // 正在重置
            break;
            
        case CBManagerStateUnknown:
            
            // 未知状态
            break;
            
        default:
            break;
    }
}


- (void)peripheralManager:(CBPeripheralManager *)peripheral didAddService:(nonnull CBService *)service error:(nullable NSError *)error {
    
    if(error)
    {
        NSLog(@"添加服务出现错误：%@",[error localizedDescription]);
        return;
    }
    NSLog(@"添加service运行成功");
}


- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
    
    if(error)
    {
        NSLog(@"开启广播出现错误：%@",[error localizedDescription]);
        return;
    }
    NSLog(@"开始广播成功");
}

// 记录订阅的 centrals
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
    
    // 记录已订阅当前特征值的manager
    if([characteristic.UUID isEqual:[CBUUID UUIDWithString: @"68753A44-4D6F-1226-9C60-0050E4C00068"]]) {

        // 表示当前连接的central 一次通知，能传送的最大长度 bytes ,cbperipheral没有此属性
        NSInteger maxLengthToSend = central.maximumUpdateValueLength;
        [self addCentralToDeviceArray:central maxMessageLength:maxLengthToSend];
        
        // 至此，作为peripheral端的连接已经完成
        if([self.unNamedDelegate respondsToSelector:@selector(connectionIsOk)]) {
            
            [self.unNamedDelegate connectionIsOk];
        }
        
        self.chatRole = @"peripheral";
        [self.peripheralManager stopAdvertising];
    }
    NSLog(@"didSubscribeToCharacteristic run");
}

// central端通过关闭蓝牙，或者超出连接距离而断开（app连接被动断开）
// 取消订阅可以主动关闭，这里为了区分主动被动，避免手动取消订阅
- (void)peripheralManager:(CBPeripheralManager *)peripheral central:(CBCentral *)central didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
    
    for(NSInteger i=0; i<self.centralsFollow.count; ++i)
    {
        if([central isEqual:[self.centralsFollow objectAtIndex:i]])
        {
            [self.centralsFollow removeObjectAtIndex:i];
            if(self.centralsMaxMessageLength.count > i) {
                [self.centralsMaxMessageLength removeObjectAtIndex:i];
            }
            break;
        }
    }
    
    // 当前并未主动关闭
    if([self.unNamedDelegate respondsToSelector:@selector(shutDownByBlueTooth)] && !self.closeInitiative) {
        
        [self.unNamedDelegate shutDownByBlueTooth];
    }
    [self connectionRelease];
}

// peripheral端收到读请求
- (void)peripheralManager:(CBPeripheralManager *)peripheral didReceiveReadRequest:(CBATTRequest *)request {
    
    // 读请求，必须回复。--统一回复成功
    [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
}

// 外设收到写请求--即收到数据
// 对方主动关闭连接
- (void) peripheralManager: (CBPeripheralManager *) peripheral didReceiveWriteRequests:(NSArray *) requests {
    
    // 经过测试 收到数据最大值限制 --512 bytes
    CBATTRequest  *requestRecv = requests.lastObject;
    
    NSString *response = [[ NSString alloc] initWithData:requestRecv.value encoding:NSUTF8StringEncoding];
    NSLog(@"回复内容：%@ ",response);
    
    // 外设  收到请求  回复状态为成功
    // 根据当前值符合约定与否，返回相应的result error值，发送方等候超时10秒
    [peripheral respondToRequest:requestRecv withResult:CBATTErrorSuccess];
    
    // 对方主动关闭连接
    if([response isEqualToString:self.peripheralStopChatMessage]) {
        if([self.unNamedDelegate respondsToSelector:@selector(shutDownByPeer)]) {
            
            [self.unNamedDelegate shutDownByPeer];
        }
        
        self.closeInitiative = YES;
        [self connectionRelease];
        
        NSLog(@"外设端被主动关闭");
        return;
    }
    
    if([self.unNamedDelegate respondsToSelector:@selector(recvMessage:)]) {
        
        [self.unNamedDelegate recvMessage:response];
    }
}

// 先前更新特征值失败之后回调，在回调中重新更新
- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
    
    [self.peripheralManager updateValue:self.tempCharacteristicValue
                      forCharacteristic:self.characteristicForAdv
                   onSubscribedCentrals:self.centralsFollow];
}



#pragma mark - private methods

// 外设端添加收听central，和当前能发送数据的最大长度
- (void) addCentralToDeviceArray :(CBCentral *)central maxMessageLength:(NSInteger) maxLength {
    
    [self.centralsFollow addObject:central];
    [self.centralsMaxMessageLength addObject:[NSNumber numberWithInteger:maxLength]];
}

//根据信号响度排序设备列表
- (void)sortDeviceArray {
    
    if(self.deviceArray.count < 2)
    {
        return;
    }
    [self.deviceArray sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        NSDictionary *ob1 = (NSDictionary *)obj1;
        NSDictionary *ob2 = (NSDictionary *)obj2;
        
        NSNumber *RSSI1 = [ob1 objectForKey:@"RSSI"];
        NSNumber *RSSI2 = [ob2 objectForKey:@"RSSI"];
        
        if(RSSI1 >= RSSI2){
            return NSOrderedDescending;
        }
        else {
            return NSOrderedSame;
        }
    }];
}

// 被timer调用，用于查找可连接的对象
- (void)searchDevice {
    
    if(!self.centralManager) {
        
        self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    }
    
    ++self.scanTimes;
    if(self.scanTimes % 3 == 0) {
        
        [self.deviceArray removeAllObjects];
        if([self.unNamedDelegate respondsToSelector:@selector(deviceArrayIsChanged)]) {
            
            [self.unNamedDelegate deviceArrayIsChanged];
        }
    }
    
    // CBCentralManagerScanOptionAllowDuplicatesKey为YES时，刷新频率极高，CPU使用率极高 ip6在 30%左右。
    [self.centralManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey:@(NO)}];
}

// 蓝牙未授权
- (void) bluetoothUnAuthorized {
    
    if([self.unNamedDelegate respondsToSelector:@selector(bluetoothUnAuthorized)]) {
        [self.unNamedDelegate bluetoothUnAuthorized];
    }
}

// 通信接口
- (void) sendMessageFromCentral :(NSString *)message {
    
    NSData *infoData = [message dataUsingEncoding:NSUTF8StringEncoding];
    if(!self.peripheralsFollow || self.peripheralsFollow.count == 0) {
        return;
    }
    [self.peripheralsFollow[0] writeValue:infoData
                        forCharacteristic:self.characteristicFollow
                                     type:CBCharacteristicWriteWithResponse];
}
- (void) sendMessageFromPeripheral :(NSString *)message {
    
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    self.tempCharacteristicValue = data;
    if(!self.centralsFollow || self.centralsFollow.count == 0) {
        
    }
    [self.peripheralManager updateValue:data
                      forCharacteristic:self.characteristicForAdv
                   onSubscribedCentrals:self.centralsFollow];
}

// 主动关闭连接  双方
- (void) shutDownConnectionFromCentral {
    
    [self sendMessageToPeer:self.peripheralStopChatMessage];
    [self connectionRelease];
}
- (void) shutDownConnectionFromPeripheral {
    
    [self sendMessageToPeer:self.peripheralStopChatMessage];
    //[self connectionRelease];  //外设主动关闭不走释放，因为不是真正释放连接
}

// 我方(只可能是外设端)被动关闭（不管对方主动被动），主动关闭后释放
// 释放连接
- (void) connectionRelease {
    
    //考虑到对方无法真正主动关闭，因此我方收到消息后，主动关闭。
    if(self.peripheralsFollow.count != 0 && [self.chatRole isEqualToString:@"central"]) {
        
        [self.peripheralsFollow[0] setNotifyValue:NO forCharacteristic:self.characteristicFollow];
//        [self.centralManager cancelPeripheralConnection:self.peripheralsFollow[0]];
//        断开连接不调用cancel方法，因为会造成central回调 diddisconnect方法，和对方被动关闭混淆
//        所以实际保持连接，不监听特征值
        [self.centralManager stopScan];
    }
    
    //对方可以真正主动关闭连接，因此简单释放变量即可。
    if(self.centralsFollow.count != 0 && [self.chatRole isEqualToString:@"peripheral"]) {
        
        [self.peripheralManager stopAdvertising];
    }
    [self releaseProperties];
}

@end




