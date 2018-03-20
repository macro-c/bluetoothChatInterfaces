//
//  bluetooth.m
//  blueToothInterface
//
//  Created by ChenHong on 2018/3/6.
//  Copyright © 2018年 macro-c. All rights reserved.
//

#import "bluetooth.h"
#define WEAK_SELF __weak typeof(self) weakSelf = self


/**
 消息类型
 */
typedef NS_ENUM(NSInteger, DDBluetoothMessageType) {
    
    DDBluetoothMessageTypeChat = 1,     //文字聊天信息
    DDBluetoothMessageTypeNotification, //文字通知信息：连接成功发送设备信息，主动断开发送断开信息
    DDBluetoothMessageTypeImageInfo,    //图片分片信息
    DDBluetoothMessageTypeImageData,    //图片分片数据：图片传输过程中双方使用此信息
};



@interface DDBluetooth()


/**
 central端使用属性
 **/
@property (nonatomic, strong) CBCentralManager *centralManager;
// central可用状态（保留，程序未使用）
@property (nonatomic, assign) BOOL centralAvailable;
// 扫描计数器
@property (nonatomic, strong) NSTimer *scanDeviceTimer;
// 扫描次数，用于定时清理设备列表
// 因为扫描的返回值只是当前可连接的设备，因此需要定时清理设备，尽量保证设备列表的设备有效
@property (nonatomic, assign) NSInteger scanTimes;
// 保存收听的peripherals
@property (nonatomic, strong) NSMutableArray<CBPeripheral *> *peripheralsFollow;
// 当前central所监听的特征
@property (nonatomic, strong) CBCharacteristic *characteristicFollow;
// 暂存当前正在遍历服务和特征值的 CBPeripheral实例，
// 此实例需要暂存，否则很可能使此次连接失效，强引用使其保持有效
@property (nonatomic, strong) CBPeripheral *peripheralToHandle;
// 当前主动连接对象的名称
@property (nonatomic, strong) NSString *peripheralName;


/**
 peripheral端使用属性
 */
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
// 保存被收听的centrals
@property (nonatomic, strong) NSMutableArray<CBCentral *> *centralsFollow;
// 保存发送至每个central的消息最长值
@property (nonatomic, strong) NSMutableArray<NSNumber *> *centralsMaxMessageLength;
// 当前外设的服务和特征
@property (nonatomic, strong) CBMutableCharacteristic *characteristicForAdv;
@property (nonatomic, strong) CBMutableService *service;
@property (nonatomic, strong) NSString *serviceUUID;
@property (nonatomic, strong) NSString *characterUUID;
// 自定义用户名
@property (nonatomic, strong) NSString *userName;
// 暂存更新的特征值
// 当外设端忙碌时不能立即发送，需要暂存至可用时发送
@property (nonatomic, strong) NSData *tempCharacteristicValue;



/**
 公共属性
 */
// 蓝牙授权状态
@property (nonatomic, assign) BOOL appAuthorizedStatus;
// 针对应用间安全验证--思路：对方随机产生一个数字，在appUUID中作为索引找到相应字符,返回验证（双向）
@property (nonatomic, strong) NSString *appUUID;
// 用户名前缀，固定，central扫描设备时首先筛选name前缀
@property (nonatomic, strong) NSString *userNamePrifix;
// 固定消息，表示peripheral端主动关闭
@property (nonatomic, strong) NSString *peripheralStopChatMessage;
// 角色信息，连接中当前一方的角色 true表示peripheral，false表示central
@property (nonatomic, strong) NSString *chatRole;
// 发送消息成功或者失败的回调
@property (nonatomic, copy) void (^sendMsgAction)(BOOL);
// 发送图片结果状态回调
@property (nonatomic, copy) void (^sendImageAction)(BOOL);
// 收到消息后回复内容，发送方以此确定发送成功
@property (nonatomic, strong) NSString *replyMessage;


// 文字消息--发送超时+发送接口互斥访问
// 收到对方回复
@property (nonatomic, assign) BOOL receivdReply;
// 消息超时
@property (nonatomic, assign) BOOL replyOverTime;
// 成功回复，或超时
@property (nonatomic, assign) BOOL sendMsgHasHandled;
// 消息超时计时器
@property (nonatomic, strong) NSTimer *sendChatMsgTikTok;

// 图片消息--发送超时+发送接口互斥访问
// 收到图片发送完成回复
@property (nonatomic, assign) BOOL imageReceivedReply;
// 图片发送超时
@property (nonatomic, assign) BOOL imageReplyOverTime;
// 发送完成，或超时
@property (nonatomic, assign) BOOL imageSendMsgHandled;
// 图片超时计时器
// 发送、接收端通用计时
@property (nonatomic, strong) NSTimer *imageSendTikTok;



// 标识已经主动关闭（被自己或对方），为YES则忽略之后的被动关闭回调
// initiative主动的
@property (nonatomic, assign) BOOL closeInitiative;


// 发送图片等大文件 分片数组
@property (nonatomic, strong) NSMutableArray<NSString *> *imageDataPiecesArraySend;
// 接收图片  分片数组
@property (nonatomic, strong) NSMutableArray<NSString *> *imageDataPiecesArrayRecv;
// 接收图片，分片大小
@property (nonatomic, assign) NSInteger recvImagePieceSize;
// 接收图片，分片总数
@property (nonatomic, assign) NSInteger recvImagePieceCount;
// 接收图片，图总大小
@property (nonatomic, assign) NSInteger recvImageDataSize;
// 接收图片，已接收分片数
@property (nonatomic, assign) NSInteger recvImageDataPieceSumCount;
// 标识当前在传输图片
@property (nonatomic, assign) BOOL centralImageSendMode;
@property (nonatomic, assign) BOOL peripheralImageSendMode;
@property (nonatomic, assign) BOOL centralImageRecvMode;
@property (nonatomic, assign) BOOL peripheralImageRecvMode;

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

    self.peripheralStopChatMessage = @"bye$#!0202";
    self.chatRole = @"";
    
    self.centralsFollow = [[NSMutableArray alloc] init];
    self.peripheralsFollow = [[NSMutableArray alloc] init];
    self.centralsMaxMessageLength = [[NSMutableArray alloc] init];
    // 默认被动关闭
    self.closeInitiative = NO;
    // 双方收到消息之后回发此信息，对此消息不再回复
    self.replyMessage = @"receiced$&9843";
    
    // 回复，超时，发消息结果
    self.receivdReply = NO;
    self.replyOverTime = NO;
    self.sendMsgHasHandled = YES;
    
    self.imageReceivedReply = NO;
    self.imageReplyOverTime = NO;
    self.imageSendMsgHandled = YES;
    
    // 图片传输相关
    self.centralImageSendMode = NO;
    self.peripheralImageSendMode = NO;
    self.centralImageRecvMode = NO;
    self.peripheralImageRecvMode = NO;
    self.recvImageDataPieceSumCount = 0;
    
    self.tempCharacteristicValue = [[NSData alloc] init];
}

- (instancetype) init {
    
    self = [super init];
    [self initProperties];
    return self;
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
    if(self.sendChatMsgTikTok) {
        [self.sendChatMsgTikTok invalidate];
        self.sendChatMsgTikTok = nil;
    }
    if(self.imageSendTikTok) {
        [self.imageSendTikTok invalidate];
        self.imageSendTikTok = nil;
    }
    self.closeInitiative = NO;
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

#pragma mark - 发送文字 、发送图片

- (void) sendMessageToPeer:(NSString *)message {
    
    NSDictionary *messageFromAll = [self generateChatMessage:message];
    //外设端
    if([self.chatRole isEqualToString:@"peripheral"]) {
        
        [self sendMessageFromPeripheral:messageFromAll];
    }
    else {
        
        [self sendMessageFromCentral:messageFromAll];
    }
    // 区别是否需要 发送消息回调
    self.sendMsgAction = nil;
}


- (BOOL) sendMessageToPeer:(NSString *)message sendAction:(void (^)(BOOL success))action {
    
    if(!self.sendMsgHasHandled) {
        
        // 当前带回调发送消息模式，必须等待返回值结果才能继续发送
        return NO;
    }
    
    self.receivdReply = NO;
    [self sendMessageToPeer:message];
    if(action) {
        
        self.sendMsgAction = action;
        self.receivdReply = NO;
        self.replyOverTime = NO;
        self.sendMsgHasHandled = NO;
        
        WEAK_SELF;
        if(self.sendChatMsgTikTok) {
            [self.sendChatMsgTikTok invalidate];
            self.sendChatMsgTikTok = nil;
        }
        self.sendChatMsgTikTok = [NSTimer timerWithTimeInterval:1 repeats:NO block:^(NSTimer * _Nonnull timer) {
            
            if(weakSelf.sendMsgAction && !self.receivdReply) {
                
                weakSelf.sendMsgAction(NO);
                weakSelf.replyOverTime = YES;
                weakSelf.sendMsgHasHandled = YES;
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:self.sendChatMsgTikTok forMode:NSRunLoopCommonModes];
    }
    
    return YES;
}

// 暂时取消不带回调，不带超时，不带互斥的发送接口
// ---做工具函数用
- (BOOL) sendImageToPeer:(UIImage *)image {

    // 区别是否需要 发送消息回调
    self.sendImageAction = nil;
    //外设端
    if([self.chatRole isEqualToString:@"peripheral"]) {

        return [self sendImageInfoFromPeripheral:image];
    }
    else {

        return [self sendImageInfoFromCentral:image];
    }
}

// 带回调的发送图片消息，超时限制，互斥限制
- (BOOL) sendImageToPeer:(UIImage *)image sendAction:(void (^)(BOOL))action {
    
    if(!self.imageSendMsgHandled) {
        
        // 当前带回调发送消息模式，必须等待返回值结果才能继续发送
        return NO;
    }
    
    self.imageReceivedReply = NO;
    [self sendImageToPeer:image];
    if(action) {
        
        self.sendImageAction = action;
        self.imageReceivedReply = NO;
        self.imageReplyOverTime = NO;
        self.imageSendMsgHandled = NO;
        
        WEAK_SELF;
        if(self.imageSendTikTok) {
            
            [self.imageSendTikTok invalidate];
            self.imageSendTikTok = nil;
        }
        self.imageSendTikTok = [NSTimer timerWithTimeInterval:3 repeats:NO block:^(NSTimer * _Nonnull timer) {
            
            if(weakSelf.sendMsgAction && !self.imageReceivedReply) {
                
                weakSelf.sendImageAction(NO);
                weakSelf.imageReplyOverTime = YES;
                //weakSelf.imageSendMsgHandled = YES;  //不在这里handle
                // 处理发送超时
                [self handleSendImageDataOverTime];
            }
        }];
        
    }
    
    return YES;
}



// 主动关闭 (不走任何可能混淆被动关闭的方式，如取消订阅)
- (void) shutDownConnection {
    
    if(self.peripheralsFollow.count != 0 && [self.chatRole isEqualToString:@"central"]) {
        
        NSDictionary *stopChatMessage = [self generateNotificationMessage:self.peripheralStopChatMessage];
        [self sendMessageFromCentral:stopChatMessage];
        [self.centralManager stopScan];
        [self releaseProperties];
    }
    
    if(self.centralsFollow.count != 0 && [self.chatRole isEqualToString:@"peripheral"]) {
        
        // peripheral端无法以接口关闭连接，并让对方感知；所以发送 peripheralStopChatMessage 消息，表示外设端已关闭
        NSDictionary *stopChatMessage = [self generateNotificationMessage:self.peripheralStopChatMessage];
        [self sendMessageFromPeripheral:stopChatMessage];
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
    
    NSInteger namePrefixLength = self.userNamePrifix.length;
    self.peripheralName = [[self.deviceArray[index] objectForKey:@"peripheralName"] substringFromIndex:namePrefixLength];
    
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
    
    // ,CBConnectPeripheralOptionNotifyOnNotificationKey:@(YES)
    // central端！！！！！当程序位于后台，且收到订阅消息时，会收到系统级提示
    
    NSLog(@"开始连接设备");
}

// 连接某台设备
// arg--设备的广播名
- (void) connectDeviceWithName:(NSString *)deviceName {
    
    NSInteger index = 0;
    NSInteger deviceCount = self.deviceArray.count;
    NSString *tempDeviceName;
    for(; index<deviceCount; ++index) {
        
        tempDeviceName = [self.deviceArray[index] objectForKey:@"peripheralName"];
        if([tempDeviceName isEqualToString:deviceName]) {
            
            break;
        }
    }
    
    [self connectDeviceAtIndex:index];
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
            [self bluetoothUnAvailable];
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
            NSLog(@"default state");
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
                [self.deviceArray replaceObjectAtIndex:i withObject:dict];
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
    [self shutDownByBlueTooth];
    
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
            
            if([self.unNamedDelegate respondsToSelector:@selector(connectionIsOk:)]) {
                
                NSMutableDictionary *myInfo = [[NSMutableDictionary alloc] init];
                [myInfo setObject:self.peripheralName forKey:DDBluetoothMessagePeerNameKey];
                NSDictionary *helloMessageToSelf = [self generateHelloMessage:myInfo];
                [self.unNamedDelegate connectionIsOk:helloMessageToSelf];
                
                //central端发送自己信息给对端，使对方连接成功后的回调附加消息，复用peerInfo对象
                NSMutableDictionary *peerInfo = [[NSMutableDictionary alloc] init];
                [peerInfo setObject:self.userName forKey:DDBluetoothMessagePeerNameKey];
                NSDictionary *helloMessageToPeer = [self generateHelloMessage:peerInfo];
                [self sendMessageFromCentral:helloMessageToPeer];
                
                //关闭广播
                [self.peripheralManager stopAdvertising];
                //[self.centralManager stopScan];
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
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:data
                                                            options:NSJSONReadingMutableContainers
                                                              error:nil];
    
    BOOL isChatMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                          integerValue]== DDBluetoothMessageTypeChat;
    BOOL isNotificationMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                                  integerValue]==DDBluetoothMessageTypeNotification;
    BOOL isImageInfoMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                           integerValue]== DDBluetoothMessageTypeImageInfo;
    BOOL isImageDataMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                               integerValue] ==DDBluetoothMessageTypeImageData;
    BOOL isSendOverTimeMessage = [[message objectForKey:DDBluetoothMessageImageOverTimerKey] boolValue];
    
    NSString *info = [message objectForKey:DDBluetoothMessageContentKey];
    // 判断是否是固定回复，是否需要固定回复
    if(isNotificationMessage && [info isEqualToString:self.replyMessage]) {
        
        if(self.sendMsgAction && !self.replyOverTime) {
        
            self.sendMsgAction(YES);
            self.receivdReply = YES;
            self.sendMsgHasHandled = YES;
            
            if(self.sendChatMsgTikTok) {
                
                [self.sendChatMsgTikTok invalidate];
                self.sendChatMsgTikTok = nil;
            }
        }
        return;
    }
    // 对端主动关闭
    else if(isNotificationMessage && [info isEqualToString:self.peripheralStopChatMessage]) {
        if([self.unNamedDelegate respondsToSelector:@selector(shutDownByPeer)]) {
            
            [self.unNamedDelegate shutDownByPeer];
        }
        self.closeInitiative = YES;
        [self connectionRelease];
        
        NSLog(@"central端被主动关闭");
        return;
    }
    else if(isChatMessage) {
        
        [self handleChatMessageFromCentral:YES message:message];
        return;
    }
    // 图片预备信息，切换当前传输图片mode，准备相应接收缓存区，记录图片的简单校验信息
    else if(isImageInfoMessage) {
        
        self.centralImageRecvMode = YES;
        [self handleImageInfoMessage:message];
    }
    else if(isImageDataMessage) {
        
        if(!self.centralImageRecvMode) {
            return;
        }
        // 发送端超时，接收端处理
        if(isSendOverTimeMessage) {
            [self handleRecvImageDataOverTime];
        }
        
        [self handleImageDataMessage:message];
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
            [self bluetoothUnAvailable];
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
        // 由于peripheral端无法主动得知对方信息，所以这里回调函数无法返回peerInfo
        // if([self.unNamedDelegate respondsToSelector:@selector(connectionIsOk:)]) {
        
            //[self.unNamedDelegate connectionIsOk:];
            //关闭广播
            //[self.peripheralManager stopAdvertising];
        //}
        
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
    [self shutDownByBlueTooth];
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
    
    
    
    // 外设  收到请求  回复状态为成功
    // 根据当前值符合约定与否，返回相应的result error值，发送方等候超时10秒
    //******************************一个神奇的语句，注掉下行代码，会导致程序不规则的走当前方法**********************************
    [peripheral respondToRequest:requestRecv withResult:CBATTErrorSuccess];
    
    
    
    
    NSData *data = requestRecv.value;
    // 读取特征中携带的数据
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:data
                                                            options:NSJSONReadingMutableContainers
                                                              error:nil];
//    NSInteger messageType =
    BOOL isChatMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                          integerValue]== DDBluetoothMessageTypeChat;
    BOOL isNotificationMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                                  integerValue]==DDBluetoothMessageTypeNotification;
    BOOL isImageInfoMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                           integerValue]== DDBluetoothMessageTypeImageInfo;
    BOOL isImageDataMessage = [[message objectForKey:DDBluetoothMessageTypeKey]
                               integerValue] == DDBluetoothMessageTypeImageData;
    BOOL isImageSendOverTime = [[message objectForKey:DDBluetoothMessageImageOverTimerKey] boolValue];
    
    NSString *info = [message objectForKey:DDBluetoothMessageContentKey];
    
//    NSString *response = [[ NSString alloc] initWithData:requestRecv.value encoding:NSUTF8StringEncoding];

    // 判断是否是固定回复，是否需要固定回复
    if(isNotificationMessage && [info isEqualToString:self.replyMessage]) {
        
        if(self.sendMsgAction && !self.replyOverTime) {
            
            self.receivdReply = YES;
            self.sendMsgAction(YES);
            self.sendMsgHasHandled = YES;
            
            if(self.sendChatMsgTikTok) {
                
                [self.sendChatMsgTikTok invalidate];
                self.sendChatMsgTikTok = nil;
            }
        }
        return;
    }
    // hello消息
    else if(isNotificationMessage && [info isEqualToString:@"helloMessage"]) {
        
        // 此时认为 peripheral端完成连接
        if([self.unNamedDelegate respondsToSelector:@selector(connectionIsOk:)]) {
        
            [self.unNamedDelegate connectionIsOk:message];
            //关闭广播
            [self.peripheralManager stopAdvertising];
        }
        
        return;
    }
    else if(isChatMessage) {
        
        [self handleChatMessageFromCentral:NO message:message];
    }
    else if(isImageInfoMessage) {
        
        [self handleImageInfoMessage:message];
        self.peripheralImageRecvMode = YES;
    }
    else if(isImageDataMessage) {
        
        if(!self.peripheralImageRecvMode) {
            return;
        }
        // 发送端超时，接收端处理
        if(isImageSendOverTime) {
            
            [self handleRecvImageDataOverTime];
        }
        
        [self handleImageDataMessage:message];
    }
    
    // 对方主动关闭连接
    if(isNotificationMessage && [info isEqualToString:self.peripheralStopChatMessage]) {
        if([self.unNamedDelegate respondsToSelector:@selector(shutDownByPeer)]) {
            
            [self.unNamedDelegate shutDownByPeer];
        }
        
        self.closeInitiative = YES;
        [self connectionRelease];
        
        NSLog(@"外设端被主动关闭");
        return;
    }
}

// 先前更新特征值失败之后回调，在回调中重新更新
- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
    
    [self.peripheralManager updateValue:self.tempCharacteristicValue
                      forCharacteristic:self.characteristicForAdv
                   onSubscribedCentrals:self.centralsFollow];
}



#pragma mark - private methods

// 文字消息处理函数
- (void) handleChatMessageFromCentral:(BOOL)fromCentral message:(NSDictionary *)message {
    
    if(self.unNamedDelegate && [self.unNamedDelegate respondsToSelector:@selector(recvMessage:)]) {
        
        NSString *chatStringMessage = [message objectForKey:DDBluetoothMessageContentKey];
        [self.unNamedDelegate recvMessage:chatStringMessage];
    }
    NSDictionary *replyMessage = [self generateNotificationMessage:self.replyMessage];
    if(fromCentral) {
        [self sendMessageFromCentral:replyMessage];
    }
    else {
        [self sendMessageFromPeripheral:replyMessage];
    }
}

// 图片准备信息处理函数
// 接收到info消息时开始计算接收超时
- (void) handleImageInfoMessage :(NSDictionary *)message {
    
    NSInteger imageDataSize = [[message objectForKey:DDBluetoothMessageImageSizeKey] integerValue];
    NSInteger imagePieceCount = [[message objectForKey:DDBluetoothMessageImageArrayLengthKey] integerValue];
    NSInteger imagePieceSize = [[message objectForKey:DDBluetoothMessageImagePieceSizeKey] integerValue];
    
    self.recvImageDataSize = imageDataSize;
    self.recvImagePieceSize = imagePieceSize;
    self.recvImagePieceCount = imagePieceCount;
    
    self.imageDataPiecesArrayRecv = [[NSMutableArray alloc] initWithCapacity:imagePieceCount];
    
    // 接收方只发 下一个分片的索引
    if([self.chatRole isEqualToString:@"central"]) {
        
        [self sendImageDataFromCentral:@"0" isSendOverTime:NO];
    }
    else {
        
        [self sendImageDataFromPeripheral:@"0" isSendOverTime:NO];
    }
    
    // 接收端开始计时
    WEAK_SELF;
    dispatch_time_t overTime = dispatch_time(DISPATCH_TIME_NOW, 3000000000); //3秒
    dispatch_after(overTime, dispatch_get_main_queue(), ^{
        
    });
}
// 接收端消息超时处理函数
- (void) handleRecvImageDataOverTime {
    
    // 重置身份
    self.centralImageRecvMode = NO;
    self.peripheralImageRecvMode = NO;
    // 重置接收记录
    self.recvImageDataSize = 0;
    self.recvImagePieceSize = 0;
    self.recvImagePieceCount = 0;
    self.recvImageDataPieceSumCount =0;
    // 释放缓冲区
    [self.imageDataPiecesArrayRecv removeAllObjects];
}
// 发送端消息超时处理
- (void) handleSendImageDataOverTime {
    
    self.imageSendMsgHandled = YES;
    [self sendImageDataToPeer:@"-1" isOverTime:YES];
    // 释放缓冲
    [self.imageDataPiecesArraySend removeAllObjects];
}
// 图片数据处理函数
- (void) handleImageDataMessage :(NSDictionary *)message {
    
    // 可能为索引（来自接收方），或图片数据（来自发送方）
    NSString *imageMessageContent = [message objectForKey:DDBluetoothMessageContentKey];
    
    // sendMode
    if(self.centralImageSendMode) {
        
        // 发送端已经超时，且已经完成超时处理。忽略消息
        if(self.imageReplyOverTime && self.imageSendMsgHandled) {
            
            return;
        }
        
        NSInteger index = [imageMessageContent integerValue];
        // 表示发送完成
        if(index == self.imageDataPiecesArraySend.count) {
            
            self.imageSendMsgHandled = YES;
            self.imageReceivedReply = YES;
            self.sendImageAction(YES);
            
            if(self.imageSendTikTok) {
                
                [self.imageSendTikTok invalidate];
                self.imageSendTikTok = nil;
            }
        }
        [self sendImageDataFromCentral:self.imageDataPiecesArraySend[index] isSendOverTime:NO];
        return;
    }
    else if(self.peripheralImageSendMode) {
        
        // 发送端已经超时，且已经完成超时处理。忽略消息
        if(self.imageReplyOverTime && self.imageSendMsgHandled) {
            
            return;
        }
        
        NSInteger index = [imageMessageContent integerValue];
        // 表示发送完成
        if(index == self.imageDataPiecesArraySend.count) {
            
            self.imageSendMsgHandled = YES;
            self.imageReceivedReply = YES;
            self.sendImageAction(YES);
            
            if(self.imageSendTikTok) {
                
                [self.imageSendTikTok invalidate];
                self.imageSendTikTok = nil;
            }
        }
        [self sendImageDataFromPeripheral:self.imageDataPiecesArraySend[index] isSendOverTime:NO];
        return;
    }
    
    
    // receiveMode
    
    // 以下为接收图片数据
    // 表示发送端已经超时，接收端释放缓冲区，重置身份
    if([imageMessageContent isEqualToString:@"-1"]) {
        
        [self handleRecvImageDataOverTime];
    }
    
    if(self.recvImageDataPieceSumCount >= self.recvImagePieceCount) {
        return;
    }
    // 简单校验数据完整，并保存数据
    if(self.recvImageDataPieceSumCount == self.recvImagePieceCount -1) {
        NSInteger lastPieceLength = self.recvImageDataSize - (self.recvImagePieceCount-1)*self.recvImagePieceSize;
        if(lastPieceLength != imageMessageContent.length) {
            NSString *resendIndex = [NSString stringWithFormat:@"%ld",self.recvImageDataPieceSumCount -1];
            // 当前索引数据要求重发
            if(self.centralImageRecvMode) {
                
                [self sendImageDataFromCentral:resendIndex isSendOverTime:NO];
            }else if(self.peripheralImageRecvMode) {
                
                [self sendImageDataFromPeripheral:resendIndex isSendOverTime:NO];
            }
        }
    }
    else {
        if(self.recvImagePieceSize != imageMessageContent.length) {
            NSString *resendIndex = [NSString stringWithFormat:@"%ld",self.recvImageDataPieceSumCount -1];
            // 当前索引要求重发
            if(self.centralImageRecvMode) {
                
                [self sendImageDataFromCentral:resendIndex isSendOverTime:NO];
            }else if(self.peripheralImageRecvMode) {
                
                [self sendImageDataFromPeripheral:resendIndex isSendOverTime:NO];
            }
        }
    }
    
    // 校验完成 保存数据 并发送下一个分片索引
    [self.imageDataPiecesArrayRecv addObject:imageMessageContent];
    self.recvImageDataPieceSumCount++;
    NSString *resendIndex = [NSString stringWithFormat:@"%ld",(long)self.recvImageDataPieceSumCount];
    if(self.centralImageRecvMode) {
        
        [self sendImageDataFromCentral:resendIndex isSendOverTime:NO];
    }else if(self.peripheralImageRecvMode) {
        
        [self sendImageDataFromPeripheral:resendIndex isSendOverTime:NO];
    }
    // 接收完毕
    if(self.recvImageDataPieceSumCount == self.recvImagePieceCount) {
        
        if([self.unNamedDelegate respondsToSelector:@selector(recvImage:)]) {
            
            NSMutableString *imageString = nil;
            // 就地 还原图像文件
            for(NSInteger i=0; i<self.recvImageDataPieceSumCount ;++i) {
                
                [imageString appendString:self.imageDataPiecesArrayRecv[i]];
            }
            // 释放
            [self.imageDataPiecesArrayRecv removeAllObjects];
            NSData *imageData = [[NSData alloc] initWithBase64EncodedString:imageString options:NSDataBase64DecodingIgnoreUnknownCharacters];
            UIImage *imageReceived = [UIImage imageWithData:imageData];
            
            [self.unNamedDelegate recvImage: imageReceived];
        }
    }
}

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
    
    if([self.unNamedDelegate respondsToSelector:@selector(bluetoothUnAvailableOnReason:)]) {
        
        [self.unNamedDelegate bluetoothUnAvailableOnReason:DDBluetoothUnAuthorized];
    }
}
// 蓝牙关闭
- (void) bluetoothUnAvailable {
    
    if([self.unNamedDelegate respondsToSelector:@selector(bluetoothUnAvailableOnReason:)]) {
        
        [self.unNamedDelegate bluetoothUnAvailableOnReason:DDBluetoothPowerOff];
    }
}
// 由于超距离，或对方关闭蓝牙，或对方强制关闭app
- (void) shutDownByBlueTooth {
    if([self.unNamedDelegate respondsToSelector:@selector(bluetoothUnAvailableOnReason:)]) {
        
        [self.unNamedDelegate bluetoothUnAvailableOnReason:DDBluetoothUnReachable];
    }
}



#pragma mark - 具体发送消息接口

// 通信接口
- (void) sendMessageFromCentral :(NSDictionary *)message {
    
    NSData *infoData = [NSJSONSerialization dataWithJSONObject:message
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    
    if(!self.peripheralsFollow || self.peripheralsFollow.count == 0) {
        return;
    }
    
    // type参数withResponse表示发送完必须等待对端的回复，
    [self.peripheralsFollow[0] writeValue:infoData
                        forCharacteristic:self.characteristicFollow
                                     type:CBCharacteristicWriteWithResponse];
}
- (void) sendMessageFromPeripheral :(NSDictionary *)message {
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:message
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    
    self.tempCharacteristicValue = data;
    if(!self.centralsFollow || self.centralsFollow.count == 0) {
        
    }
    [self.peripheralManager updateValue:data
                      forCharacteristic:self.characteristicForAdv
                   onSubscribedCentrals:self.centralsFollow];
}
// 发送图片等文件类
// 返回错误--1.尺寸超过 2.失去连接对象
/**
 由central端发送文件时调用
 函数功能：将图片文件分片，切换到central sendImage模式，并发送图片分片信息概述
 函数目的：使对端做好接收准备，设置相关校验数据，并准备接收
 */
- (BOOL) sendImageInfoFromCentral :(UIImage *)message {

    // 判断central端发送消息尺寸限制
    // 512bytes 是在iphone6 设备上的测试结果，其他设备待测试


    NSData *imageData = UIImageJPEGRepresentation(message, 1);
    NSInteger imageDataLength = [imageData length];
    
    BOOL tooBig = imageDataLength > 200*1024*1024;              // 暂定最大200兆
    if(tooBig) {
        return NO;
    }
    
    NSInteger imageDataPieceLength = 512-50;                       // 分片长度最大值减50
    NSInteger additionalOneLength = imageDataLength % imageDataPieceLength;
    NSInteger imageDataArrayLength = imageDataLength / imageDataPieceLength;
    if(additionalOneLength != 0){
        imageDataArrayLength += 1;
    }
    self.imageDataPiecesArraySend = [[NSMutableArray alloc] initWithCapacity:imageDataArrayLength];
    NSString *imageDataString = [imageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    
    //data分片
    for(NSInteger i=0; i<imageDataArrayLength; ++i) {
        NSInteger subStringLength = imageDataPieceLength;
        if(i == imageDataArrayLength -1) {
            subStringLength = additionalOneLength;
        }
        NSString *subString = [imageDataString substringWithRange:NSMakeRange(i*imageDataPieceLength, subStringLength)];
        [self.imageDataPiecesArraySend addObject:subString];
    }
    
    
    NSDictionary *imageInfoMessage = [self generateImageInfoWithImageSize:imageDataLength arrayLength:imageDataArrayLength pieceSize:imageDataPieceLength];

//    测试类型
//    NSDictionary *messageFromCentral = [self generateImageMessageData:imageData];
//    使用 dataWithJSONObject 时，参数json的顶层元素必须是 NSArray或NSDictionary，组成元素不能有NSData

    NSData *infoData = [NSJSONSerialization dataWithJSONObject:imageInfoMessage
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    
    if(!self.peripheralsFollow || self.peripheralsFollow.count == 0) {
        return NO;
    }
    
    [self.peripheralsFollow[0] writeValue:infoData
                        forCharacteristic:self.characteristicFollow
                                     type:CBCharacteristicWriteWithResponse];
    self.centralImageSendMode = YES;
    
    return YES;
}
/**
 由peripheral端发送文件时调用
 函数功能：将图片文件分片，切换到peripheral sendImage模式，并发送图片分片信息概述
 函数目的：使对端做好接收准备，设置相关校验数据，并准备接收
 */
- (BOOL) sendImageInfoFromPeripheral :(UIImage *)message {

    NSData *imageData = UIImageJPEGRepresentation(message, 1);
    NSInteger imageDataLength = [imageData length];
    
    BOOL tooBig = imageDataLength > 200*1024*1024;                                    // 暂定最大200兆
    if(tooBig) {
        return NO;
    }
    
    NSInteger imageDataPieceLength = [self.centralsMaxMessageLength[0] integerValue]-50; // 分片长度最大值减50
    NSInteger additionalOneLength = imageDataLength % imageDataPieceLength;
    NSInteger imageDataArrayLength = imageDataLength / imageDataPieceLength;
    if(additionalOneLength != 0){
        imageDataArrayLength += 1;
    }
    self.imageDataPiecesArraySend = [[NSMutableArray alloc] initWithCapacity:imageDataArrayLength];
    NSString *imageDataString = [imageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    
    //data分片
    for(NSInteger i=0; i<imageDataArrayLength; ++i) {
        NSInteger subStringLength = imageDataPieceLength;
        if(i == imageDataArrayLength -1) {
            subStringLength = additionalOneLength;
        }
        NSString *subString = [imageDataString substringWithRange:NSMakeRange(i*imageDataPieceLength, subStringLength)];
        [self.imageDataPiecesArraySend addObject:subString];
    }
    
    
    NSDictionary *imageInfoMessage = [self generateImageInfoWithImageSize:imageDataLength arrayLength:imageDataArrayLength pieceSize:imageDataPieceLength];
    
    NSData *infoData = [NSJSONSerialization dataWithJSONObject:imageInfoMessage
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    
    if(!self.peripheralsFollow || self.peripheralsFollow.count == 0) {
        return NO;
    }
    
    [self.peripheralsFollow[0] writeValue:infoData
                        forCharacteristic:self.characteristicFollow
                                     type:CBCharacteristicWriteWithResponse];
    self.peripheralImageSendMode = YES;
    
    return YES;
}
// 发送图片数据接口
// from central
- (void) sendImageDataFromCentral :(NSString *)imageDataMessage isSendOverTime:(BOOL)overTime {
    
    NSDictionary *infoDic = [self generateImageMessage:imageDataMessage isSendOverTime:overTime];
    NSData *infoData = [NSJSONSerialization dataWithJSONObject:infoDic
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    
    if(!self.peripheralsFollow || self.peripheralsFollow.count == 0) {
        return;
    }
    [self.peripheralsFollow[0] writeValue:infoData
                        forCharacteristic:self.characteristicFollow
                                     type:CBCharacteristicWriteWithResponse];
}
// 发送图片数据接口
// from peripheral
- (void) sendImageDataFromPeripheral :(NSString *)imageDataMessage isSendOverTime:(BOOL)overTime {
    
    NSDictionary *infoDic = [self generateImageMessage:imageDataMessage isSendOverTime:overTime];
    NSData *data = [NSJSONSerialization dataWithJSONObject:infoDic
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    
    self.tempCharacteristicValue = data;
    if(!self.centralsFollow || self.centralsFollow.count == 0) {
        
    }
    [self.peripheralManager updateValue:data
                      forCharacteristic:self.characteristicForAdv
                   onSubscribedCentrals:self.centralsFollow];
}
- (void) sendImageDataToPeer :(NSString *)imageData isOverTime:(BOOL)overTime {
    
    if([self.chatRole isEqualToString:@"sentral"]) {
        
        [self sendImageDataFromCentral:imageData isSendOverTime:overTime];
    }
    else if([self.chatRole isEqualToString:@"peripheral"]) {
        
        [self sendImageDataFromPeripheral:imageData isSendOverTime:overTime];
    }
}

#pragma mark - 消息封装
// 消息封装接口
// 发送聊天消息
- (NSDictionary *) generateChatMessage :(NSString *)message {
    
    NSMutableDictionary *retMsg = [[NSMutableDictionary alloc] init];
    
    NSNumber *messageTypeChat = [NSNumber numberWithInt : DDBluetoothMessageTypeChat];
    [retMsg setObject:messageTypeChat forKey:DDBluetoothMessageTypeKey];
    [retMsg setObject:message forKey:DDBluetoothMessageContentKey];
    
    return [retMsg copy];
}
// 发送通知消息
- (NSDictionary *) generateNotificationMessage :(NSString *)message {
    
    NSMutableDictionary *retMsg = [[NSMutableDictionary alloc] init];
    
    NSNumber *messageTypeNotification = [NSNumber numberWithInt : DDBluetoothMessageTypeNotification];
    [retMsg setObject:messageTypeNotification forKey:DDBluetoothMessageTypeKey];
    [retMsg setObject:message forKey:DDBluetoothMessageContentKey];
    
    return [retMsg copy];
}
// 发送自己信息给对端（给peripheral端）
- (NSDictionary *) generateHelloMessage :(NSDictionary *)message {
    
    NSNumber *messageTypeNotification = [NSNumber numberWithInt : DDBluetoothMessageTypeNotification];
    
    NSMutableDictionary *returnDic = [message mutableCopy];
    [returnDic setObject:messageTypeNotification forKey:DDBluetoothMessageTypeKey];
    [returnDic setObject:@"helloMessage" forKey:DDBluetoothMessageContentKey];
    
    return [returnDic copy];
}
// 图片 传输过程中，双方都是用此接口生成消息 message对于发送端是图片数据，对于接收端是下一个分片的索引string
- (NSDictionary *) generateImageMessage :(NSString *)message isSendOverTime:(BOOL)overTime {

    NSMutableDictionary *retMsg = [[NSMutableDictionary alloc] init];

    NSNumber *messageTypeImage = [NSNumber numberWithInt : DDBluetoothMessageTypeImageData];
    [retMsg setObject:messageTypeImage forKey:DDBluetoothMessageTypeKey];
    [retMsg setObject:message forKey:DDBluetoothMessageContentKey];
    [retMsg setObject:[NSNumber numberWithBool:overTime] forKey:DDBluetoothMessageImageOverTimerKey];

    return [retMsg copy];
}
// 图片的准备信息
- (NSDictionary *) generateImageInfoWithImageSize:(NSInteger)size arrayLength:(NSInteger )arrayLen pieceSize:(NSInteger)pieceSize {
    
    NSMutableDictionary *imageInfo = [[NSMutableDictionary alloc] init];
    
    NSNumber *messageTypeImageInfo = [NSNumber numberWithInt:DDBluetoothMessageTypeImageInfo];
    [imageInfo setObject:messageTypeImageInfo forKey:DDBluetoothMessageTypeKey];
    [imageInfo setObject:[NSNumber numberWithInteger:size] forKey:DDBluetoothMessageImageSizeKey];
    [imageInfo setObject:[NSNumber numberWithInteger:arrayLen] forKey:DDBluetoothMessageImageArrayLengthKey];
    [imageInfo setObject:[NSNumber numberWithInteger:pieceSize] forKey:DDBluetoothMessageImagePieceSizeKey];
    
    return [imageInfo copy];
}


#pragma mark - 断开连接
// 主动关闭连接  双方
- (void) shutDownConnectionFromCentral {
    
    NSDictionary *stopMessage = [self generateNotificationMessage:self.peripheralStopChatMessage];
    [self sendMessageFromCentral:stopMessage];
    [self connectionRelease];
}
- (void) shutDownConnectionFromPeripheral {
    
    NSDictionary *stopMessage = [self generateNotificationMessage:self.peripheralStopChatMessage];
    [self sendMessageFromPeripheral:stopMessage];
    //[self connectionRelease];  //外设主动关闭不走释放，因为不是真正释放连接
}

// 我方(只可能是外设端)被动关闭（不管对方主动被动），主动关闭后释放
// 释放连接
- (void) connectionRelease {
    
    //考虑到对方无法真正主动关闭，因此我方收到消息后，主动关闭。
    if(self.peripheralsFollow.count != 0 && [self.chatRole isEqualToString:@"central"]) {
        
        [self.peripheralsFollow[0] setNotifyValue:NO forCharacteristic:self.characteristicFollow];
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




