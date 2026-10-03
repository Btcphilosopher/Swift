import Foundation

// ============================================================
// ALARM CLOCK
// Native Swift alarm system
// ============================================================

struct Alarm: Identifiable {
    let id = UUID()
    
    var hour: Int
    var minute: Int
    var enabled: Bool
    
    var repeatDays: Set<Int> = []
    
    // 1 = Sunday
    // 2 = Monday
    // ...
    // 7 = Saturday
    
    var label: String = "Alarm"
    var snoozeMinutes: Int = 5
}

// ============================================================
// ALARM MANAGER
// ============================================================

final class AlarmManager: ObservableObject {
    
    @Published var alarms: [Alarm] = []
    
    private var timer: Timer?
    
    init() {
        startClock()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // --------------------------------------------------------
    // ADD ALARM
    // --------------------------------------------------------
    
    func addAlarm(
        hour: Int,
        minute: Int,
        repeatDays: Set<Int> = [],
        label: String = "Alarm"
    ) {
        
        let alarm = Alarm(
            hour: hour,
            minute: minute,
            enabled: true,
            repeatDays: repeatDays,
            label: label
        )
        
        alarms.append(alarm)
    }
    
    // --------------------------------------------------------
    // DELETE ALARM
    // --------------------------------------------------------
    
    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll {
            $0.id == alarm.id
        }
    }
    
    // --------------------------------------------------------
    // ENABLE / DISABLE
    // --------------------------------------------------------
    
    func toggleAlarm(_ alarm: Alarm) {
        
        guard let index = alarms.firstIndex(where: {
            $0.id == alarm.id
        }) else {
            return
        }
        
        alarms[index].enabled.toggle()
    }
    
    // --------------------------------------------------------
    // CLOCK
    // --------------------------------------------------------
    
    private func startClock() {
        
        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            
            self?.checkAlarms()
        }
    }
    
    // --------------------------------------------------------
    // CHECK ALARMS
    // --------------------------------------------------------
    
    private func checkAlarms() {
        
        let calendar = Calendar.current
        let now = Date()
        
        let components = calendar.dateComponents(
            [.hour, .minute, .weekday],
            from: now
        )
        
        guard
            let hour = components.hour,
            let minute = components.minute,
            let weekday = components.weekday
        else {
            return
        }
        
        for alarm in alarms where alarm.enabled {
            
            let timeMatches =
                alarm.hour == hour &&
                alarm.minute == minute
            
            let dayMatches =
                alarm.repeatDays.isEmpty ||
                alarm.repeatDays.contains(weekday)
            
            if timeMatches && dayMatches {
                triggerAlarm(alarm)
            }
        }
    }
    
    // --------------------------------------------------------
    // TRIGGER
    // --------------------------------------------------------
    
    private func triggerAlarm(_ alarm: Alarm) {
        
        print("🔔 ALARM: \(alarm.label)")
        print("Wake up!")
        
        // Audio / notification handling can be connected here.
        
        if alarm.repeatDays.isEmpty {
            
            if let index = alarms.firstIndex(where: {
                $0.id == alarm.id
            }) {
                alarms[index].enabled = false
            }
        }
    }
    
    // --------------------------------------------------------
    // SNOOZE
    // --------------------------------------------------------
    
    func snooze(_ alarm: Alarm) {
        
        let calendar = Calendar.current
        
        let now = Date()
        
        guard let snoozeDate = calendar.date(
            byAdding: .minute,
            value: alarm.snoozeMinutes,
            to: now
        ) else {
            return
        }
        
        let components = calendar.dateComponents(
            [.hour, .minute],
            from: snoozeDate
        )
        
        guard
            let hour = components.hour,
            let minute = components.minute
        else {
            return
        }
        
        addAlarm(
            hour: hour,
            minute: minute,
            label: "\(alarm.label) — Snoozed"
        )
    }
}


// ============================================================
// EXAMPLE
// ============================================================

let alarmManager = AlarmManager()

// Wake up at 07:30
alarmManager.addAlarm(
    hour: 7,
    minute: 30,
    label: "Wake Up"
)

// Another alarm at 08:15
alarmManager.addAlarm(
    hour: 8,
    minute: 15,
    label: "Morning Alarm"
)

print("Alarm clock running...")


import SwiftUI

struct AlarmView: View {
    
    @StateObject private var alarmManager = AlarmManager()
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                ForEach(alarmManager.alarms) { alarm in
                    
                    HStack {
                        
                        VStack(alignment: .leading) {
                            
                            Text(
                                String(
                                    format: "%02d:%02d",
                                    alarm.hour,
                                    alarm.minute
                                )
                            )
                            .font(.system(size: 42, weight: .light))
                            
                            Text(alarm.label)
                                .font(.headline)
                        }
                        
                        Spacer()
                        
                        Toggle(
                            "",
                            isOn: Binding(
                                get: {
                                    alarm.enabled
                                },
                                set: { _ in
                                    alarmManager.toggleAlarm(alarm)
                                }
                            )
                        )
                    }
                    .padding(.vertical, 8)
                }
                .onDelete { indexSet in
                    
                    for index in indexSet {
                        let alarm = alarmManager.alarms[index]
                        alarmManager.deleteAlarm(alarm)
                    }
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                
                Button {
                    
                    alarmManager.addAlarm(
                        hour: 7,
                        minute: 30,
                        label: "New Alarm"
                    )
                    
                } label: {
                    
                    Image(systemName: "plus")
                }
            }
        }
    }
}

