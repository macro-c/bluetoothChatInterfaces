//
//  bluetooth.h
//  blueToothInterface
//
//  Created by ChenHong on 2018/3/6.
//  Copyright © 2018年 macro-c. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>


// 将bluetooth的所有相关代理放在framework中
@protocol DDBluetoothDelegate<NSObject>

@required

// 用户未授权使用蓝牙
- (void) bluetoothUnAuthorized;

// 用户未打开蓝牙
- (void) bluetoothUnAvailable;

// 扫描到可连接的设备
- (void) deviceIsReadyToConnect;

// 连接设备成功
// 外设端 / 中心端
- (void) connectionIsOk;

// 收到消息
// 外设端 / 中心端
- (void) recvMessage :(NSString *)message;

// 对方主动断开
- (void) shutDownByPeer;

// 连接被动断开
// 此断开一般是某一方关闭了蓝牙，或者超出了距离，或app关闭
- (void) shutDownByBlueTooth;


@optional

// 若当前以列表或类似形式展示多台可连接设备，则需要实现当前代理
// 方法表示已经更新了可连接设备
// DDBluetooth类中的deviceArray属性有变化
- (void) deviceArrayIsChanged;


@end




@interface DDBluetooth : NSObject <CBCentralManagerDelegate,CBPeripheralManagerDelegate,CBPeripheralDelegate>

@property (nonatomic, weak) id<DDBluetoothDelegate> unNamedDelegate;

// central扫描到的设备
// 数组的元素是字典，键值分别是：@"peripheral", @"RSSI",@"peripheralName",@"deviceDistance"
// 其中当前可用的是 peripheralName(对方名称) 和RSSI(信号强度) 以及deviceDistance 和设备的估计距离
@property (nonatomic, strong) NSMutableArray *deviceArray;


// 以代理对象来初始化
// arg：delegate <DDBluetoothDelegate>类型代理对象
- (instancetype) initWithDelegate :(id<DDBluetoothDelegate>) delegate;


// 设置代理对象
// arg：delegate <DDBluetoothDelegate>类型代理对象
- (void) setDelegate :(id<DDBluetoothDelegate>) delegate;


// 开始广播和扫描
// arg：name 广播名称
- (void) startWorkingWithAdvName:(NSString *)name;


// 连接某台设备
// 应放在 deviceIsReadyToConnect 回调函数中调用
// arg：index 设备列表索引
// 当前版本 默认使用index为0---列表显示可连接设备的话，使用index版
- (void) connectDeviceAtIndex :(NSInteger)index;



// 即connectDeviceAtIndex索引为0 时
- (void) connectDevice;


// 我方主动断开
// 主从双方都有感知被动断开的能力
// 关闭当前连接（central和外设采取不同策略）
// central取消订阅 / 外设  发送某特定值
- (void) shutDownConnection;


// 发送消息
// arg：message 消息内容
- (void) sendMessageToPeer :(NSString *)message;

@end


