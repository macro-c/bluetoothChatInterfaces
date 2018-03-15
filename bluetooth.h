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

typedef NS_ENUM(NSInteger, DDBluetoothUnAvailableStatus) {
    
    DDBluetoothUnAuthorized, //未授权
    DDBluetoothPowerOff,     //蓝牙未开启
    DDBluetoothUnReachable   //蓝牙不可达--对方关闭蓝牙，或超出距离，或app强退
};

typedef NS_ENUM(NSInteger, DDBluetoothMessageType) {
    
    DDBluetoothMessageTypeChat = 1,
    DDBluetoothMessageTypeNotification,
    DDBluetoothMessageTypeImage
};

#define DDBluetoothMessageTypeKey @"DDBluetoothMessageTypeKey"
#define DDBluetoothMessageContentKey @"DDBluetoothMessageContentKey"
#define DDBluetoothMessagePeerNameKey @"DDBluetoothMessagePeerNameKey"


// 将bluetooth的所有相关代理放在framework中
@protocol DDBluetoothDelegate<NSObject>

@required


// 返回蓝牙不可用原因
// 原因参照 DDBluetoothUnAvailableStatus 枚举:未授权,蓝牙未开启,蓝牙不可达--对方关闭蓝牙，或超出距离，或app强退
- (void) bluetoothUnAvailableOnReason :(DDBluetoothUnAvailableStatus) status;

// 扫描到可连接的设备
- (void) deviceIsReadyToConnect;

// 连接设备成功
// 外设端 / 中心端
// 主动连接，被连接都走这个
- (void) connectionIsOk:(NSDictionary *)peerInfo;

// 收到消息
// 外设端 / 中心端
- (void) recvMessage :(NSString *)message;

// 收到图片
// 外设端 / 中心端
// 图片尺寸限制太小，无合理的传输策略
//- (void) recvImage :(UIImage *)image;

// 对方主动断开
- (void) shutDownByPeer;


@optional

// 若当前以列表或类似形式展示多台可连接设备，则需要实现当前代理
// 方法表示已经更新了可连接设备
// DDBluetooth类中的deviceArray属性有变化
- (void) deviceArrayIsChanged;


@end




@interface DDBluetooth : NSObject <CBCentralManagerDelegate,CBPeripheralManagerDelegate,CBPeripheralDelegate>


typedef void (^sendMsgAction)(BOOL successOrFail);


@property (nonatomic, weak) id<DDBluetoothDelegate> unNamedDelegate;


// central扫描到的设备
// 数组的元素是字典，键值分别是：@"peripheral", @"RSSI",@"peripheralName",@"deviceDistance"
// 其中当前可用的是 peripheralName(对方名称) 和RSSI(信号强度) 以及deviceDistance 和设备的估计距离
@property (nonatomic, strong) NSMutableArray *deviceArray;


// 开始广播和扫描
// arg：name 广播名称
- (void) startWorkingWithAdvName:(NSString *)name;


// 连接某台设备
// 应放在 deviceIsReadyToConnect 回调函数中调用
// arg：index 设备列表属性deviceArray 的索引
// 当前版本 默认使用index为0
- (void) connectDeviceAtIndex :(NSInteger)index;


// 连接某台设备
// 根据设备的广播名筛选
- (void) connectDeviceWithName :(NSString *)deviceName;


// 我方主动断开
// 主从双方都有感知被动断开的能力
// 关闭当前连接（central和外设采取不同策略）
// central取消订阅 / 外设  发送某特定值
- (void) shutDownConnection;


// 发送消息
// arg：message 消息内容
- (void) sendMessageToPeer :(NSString *)message;


// 发送消息
// 传递成功失败的回调
// 返回值，接口的调用成功（失败情况：上一次调用此接口未结束--未超时或回调）
// 使用时一定注意循环引用问题！！！！！！！！！
- (BOOL) sendMessageToPeer :(NSString *)message sendAction:(void (^)(BOOL success))action;





// 发送图片 暂时取消，限制于蓝牙数据报式传输，和单次传输的大小限制
//- (BOOL) sendImageToPeer :(UIImage *)image;

// 发送图片
// 传递成功失败的回调
// 返回值，接口的调用成功（失败情况：上一次调用此接口未结束--未超时或回调）
// 使用时一定注意循环引用问题！！！！！！！！！
//- (BOOL) sendImageToPeer :(UIImage *)image sendAction:(void (^)(BOOL success))action;

// 发送文件、、、、、
// 文件等其他类型应该提供其他接口
// 发送文件 + 接收文件

@end


