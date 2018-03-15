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
    
    DDBluetoothUnAuthorized,            //未授权
    DDBluetoothPowerOff,                //蓝牙未开启
    DDBluetoothUnReachable              //蓝牙不可达--对方关闭蓝牙，或超出距离，或(peripheral端)app强退
};

/**
 消息类型
 */
typedef NS_ENUM(NSInteger, DDBluetoothMessageType) {
    
    DDBluetoothMessageTypeChat = 1,     //文字聊天信息
    DDBluetoothMessageTypeNotification, //文字通知信息：连接成功发送设备信息，主动断开发送断开信息
    DDBluetoothMessageTypeImage         //图片信息
};

#define DDBluetoothMessageTypeKey @"DDBluetoothMessageTypeKey"          //消息类型标识
#define DDBluetoothMessageContentKey @"DDBluetoothMessageContentKey"    //消息内容标识
#define DDBluetoothMessagePeerNameKey @"DDBluetoothMessagePeerNameKey"  //对端设备名称（连接完成后消息）



@protocol DDBluetoothDelegate<NSObject>

@required

/**
 返回蓝牙不可用原因
 原因参照 DDBluetoothUnAvailableStatus 枚举
 arg:status 不可用原因
 */
- (void) bluetoothUnAvailableOnReason :(DDBluetoothUnAvailableStatus) status;


/**
 连接设备成功
 外设端 / 中心端
 主动连接，被连接都走这个
 arg:peerInfo 对方信息 name信息由键DDBluetoothMessagePeerNameKey取出
 */
- (void) connectionIsOk:(NSDictionary *)peerInfo;

/**
 收到消息
 外设端 / 中心端
 arg:message 收到文字消息数据
 */
- (void) recvMessage :(NSString *)message;

/**
 收到图片
 外设端 / 中心端
 arg：收到的图片数据
 */
//- (void) recvImage :(UIImage *)image;

/**
 对方主动断开
 */
- (void) shutDownByPeer;


@optional

/**
 扫描到可连接的设备
 应该在此回调方法中，执行连接操作
 
 attention！！！！！！！！！！！为保证连接成功：
 1.无用户交互情况下（不是用户点击deviceArray设备表进行连接）！不能在此方法调用之外的其他地方执行连接操作
 2.有用户交互情况下，必须实现deviceArrayIsChanged方法，实时更新devideArray设备表以及刷新呈现结果
 */
- (void) deviceIsReadyToConnect;

/**
 表示已经更新了可连接设备
 即 DDBluetooth类中的deviceArray属性有变化
 */
- (void) deviceArrayIsChanged;


@end




@interface DDBluetooth : NSObject <CBCentralManagerDelegate,CBPeripheralManagerDelegate,CBPeripheralDelegate>

/**
 发送消息成功失败状态的回调
 arg:successOrFail 成功或失败
 */
typedef void (^sendMsgAction)(BOOL successOrFail);

/**
 代理对象
 */
@property (nonatomic, weak) id<DDBluetoothDelegate> unNamedDelegate;

/**
 central扫描到的设备
 元素键值是：@"peripheral", @"RSSI",@"peripheralName",@"deviceDistance"
 当前可用信息是 peripheralName(可连接设备名称) 和RSSI(信号强度) 以及deviceDistance(大约距离)
 */
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *deviceArray;

/**
 开始广播和扫描
 arg：name 广播名称
 */
- (void) startWorkingWithAdvName:(NSString *)name;

/**
 连接某台设备
 arg：index 设备在列表deviceArray 的位置索引
 */
- (void) connectDeviceAtIndex :(NSInteger)index;

/**
 连接某台设备
 arg:deviceName 设备的广播名
 */
- (void) connectDeviceWithName :(NSString *)deviceName;

/**
 主动断开
 主从双方都有感知被动断开的能力
 */
- (void) shutDownConnection;

/**
 发送文字消息
 arg：message 消息内容
 */
- (void) sendMessageToPeer :(NSString *)message;

/**
 发送文字消息
 arg:message 消息
 arg:action 成功失败的回调
 返回值：接口的调用的成功状态（失败情况：上一次调用此接口未结束--即未超时也未回调）
 使用时一定注意循环引用问题！！！！！！！！！
 */
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


