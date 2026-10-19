import Foundation
import Testing
@testable import Alarm

@MainActor
@Suite("Alarm Synchronization and Menubar Tests")
struct AlarmSyncTests {
    
    @Test func testActiveDataKeyGeneration() {
        var settings = SyncSettings(isEnabled: true, email: "User.Name@Example.com")
        #expect(settings.activeDataKey == "macalarm:data:user_name_at_example_com:alarms")
        
        settings.email = ""
        #expect(settings.activeDataKey == "macalarm:data:default:alarms")
    }
    
    @Test func testRemoteSyncContainerEncodingAndDecoding() throws {
        let alarm = AlarmItem(
            id: UUID(),
            title: "Morning Meeting",
            hour: 9,
            minute: 0,
            repeatDays: [2, 3, 4],
            isEnabled: true,
            updatedAt: Date()
        )
        
        let container = RemoteSyncContainer(
            lastUpdated: Date(),
            deviceId: "test-device-123",
            email: "test@example.com",
            alarms: [alarm],
            deletedAlarmIds: ["deleted-uuid-1": Date().timeIntervalSince1970]
        )
        
        let encoded = try JSONEncoder().encode(container)
        let decoded = try JSONDecoder().decode(RemoteSyncContainer.self, from: encoded)
        
        #expect(decoded.deviceId == "test-device-123")
        #expect(decoded.alarms.count == 1)
        #expect(decoded.alarms.first?.title == "Morning Meeting")
        #expect(decoded.deletedAlarmIds?["deleted-uuid-1"] != nil)
    }
    
    @Test func testBackwardCompatibleAlarmDecodingWithoutUpdatedAt() throws {
        // Simulate legacy JSON that lacks updatedAt
        let legacyJson = """
        {
            "id": "\(UUID().uuidString)",
            "title": "Legacy Alarm",
            "description": "Created before updatedAt existed",
            "hour": 8,
            "minute": 15,
            "repeatDays": [2, 4, 6],
            "isEnabled": true,
            "soundType": "digital_beep",
            "singVoiceEnabled": true,
            "volumeBlast": true,
            "challengeType": "instant_click",
            "snoozeMinutes": 9,
            "isSnoozed": false
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(AlarmItem.self, from: legacyJson)
        #expect(decoded.title == "Legacy Alarm")
        #expect(decoded.updatedAt == nil)
        #expect(decoded.safeUpdatedAt == Date.distantPast)
    }
    
    @Test func testRemoteMergeKeepsNewerRemoteUpdates() {
        let store = AlarmStore()
        let alarmId = UUID()
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()
        
        let localAlarm = AlarmItem(
            id: alarmId,
            title: "Old Local Title",
            hour: 7,
            minute: 0,
            updatedAt: oldDate
        )
        store.alarms = [localAlarm]
        
        let remoteAlarm = AlarmItem(
            id: alarmId,
            title: "New Remote Title",
            hour: 7,
            minute: 30,
            updatedAt: newDate
        )
        
        store.mergeRemoteAlarms([remoteAlarm], remoteLastUpdated: newDate, remoteDeviceId: "remote-device")
        
        #expect(store.alarms.count == 1)
        #expect(store.alarms.first?.title == "New Remote Title")
        #expect(store.alarms.first?.minute == 30)
    }
    
    @Test func testRemoteMergePreservesNewerLocalOfflineEdits() {
        let store = AlarmStore()
        let alarmId = UUID()
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()
        
        let localAlarm = AlarmItem(
            id: alarmId,
            title: "New Local Offline Edit",
            hour: 7,
            minute: 45,
            updatedAt: newDate
        )
        store.alarms = [localAlarm]
        
        let remoteAlarm = AlarmItem(
            id: alarmId,
            title: "Stale Remote Title",
            hour: 7,
            minute: 0,
            updatedAt: oldDate
        )
        
        store.mergeRemoteAlarms([remoteAlarm], remoteLastUpdated: oldDate, remoteDeviceId: "remote-device")
        
        #expect(store.alarms.count == 1)
        #expect(store.alarms.first?.title == "New Local Offline Edit")
        #expect(store.alarms.first?.minute == 45)
    }
    
    @Test func testRemoteMergeAppliesTombstoneDeletions() {
        let store = AlarmStore()
        let deletedId = UUID()
        let creationDate = Date().addingTimeInterval(-7200)
        let deletionDate = Date().addingTimeInterval(-3600).timeIntervalSince1970
        
        let alarm = AlarmItem(
            id: deletedId,
            title: "Alarm To Be Deleted",
            hour: 6,
            minute: 0,
            updatedAt: creationDate
        )
        store.alarms = [alarm]
        
        store.mergeRemoteAlarms(
            [],
            remoteLastUpdated: Date(),
            remoteDeviceId: "remote-device",
            remoteDeletedIds: [deletedId.uuidString: deletionDate]
        )
        
        #expect(store.alarms.isEmpty)
        #expect(store.deletedAlarmIds[deletedId.uuidString] == deletionDate)
    }
}
