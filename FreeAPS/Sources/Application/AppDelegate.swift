import SwiftUI
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    
    // MARK: - Application Lifecycle
    
    func application(_ application: UIApplication, 
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Registra per le push notifications
        registerForPushNotifications()
        
        return true
    }
    
    // MARK: - Push Notifications Registration
    
    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            guard granted else {
                debug(.default, "❌ Permesso notifiche negato")
                return
            }
            
            debug(.default, "✅ Permesso notifiche concesso")
            
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    // MARK: - Device Token
    
    func application(_ application: UIApplication, 
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        debug(.default, "📱 Device Token: \(token)")
        
        // Salva il token localmente
        UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
        
        // Invia al backend
        sendDeviceTokenToServer(token)
    }
    
    func application(_ application: UIApplication, 
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        debug(.default, "❌ Errore registrazione push: \(error.localizedDescription)")
    }
    
    // MARK: - Ricevi Silent Push
    
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        debug(.default, "📱 Silent push ricevuta!")
        debug(.default, "Payload: \(userInfo)")
        debug(.default, "App state: \(application.applicationState == .background ? "background" : "foreground")")
        
        // Verifica se è una silent notification
        guard let aps = userInfo["aps"] as? [String: Any],
              let contentAvailable = aps["content-available"] as? Int,
              contentAvailable == 1 else {
            debug(.default, "⚠️ Non è una silent push")
            completionHandler(.noData)
            return
        }
        
        // ESEGUI LE TUE ELABORAZIONI
        performBackgroundTasks(userInfo: userInfo) { success in
            if success {
                debug(.default, "✅ Background tasks completati")
                completionHandler(.newData)
            } else {
                debug(.default, "❌ Background tasks falliti")
                completionHandler(.failed)
            }
        }
    }
    
    // MARK: - Background Tasks
    
    private func performBackgroundTasks(userInfo: [AnyHashable: Any], 
                                        completion: @escaping (Bool) -> Void) {
        debug(.default, "🔄 Inizio elaborazione background...")
        
        let startTime = Date()
        
        // OPZIONE 1: Trigger dei tuoi manager esistenti
        triggerExistingManagers()
        
        // OPZIONE 2: Chiamata API personalizzata
        performAPICall(userInfo: userInfo) { success in
            let elapsed = Date().timeIntervalSince(startTime)
            debug(.default, "⏱️ Elaborazione completata in \(String(format: "%.2f", elapsed))s")
            
            // Salva timestamp ultima sincronizzazione
            if success {
                UserDefaults.standard.set(Date(), forKey: "lastBackgroundSync")
                UserDefaults.standard.set(elapsed, forKey: "lastBackgroundSyncDuration")
            }
            
            completion(success)
        }
    }
    
    // MARK: - Trigger Existing Managers
    
    private func triggerExistingManagers() {
        // Accedi ai tuoi manager esistenti tramite il resolver
        // Questi potrebbero già fare le chiamate API necessarie
        
        if let fetchGlucose = FreeAPSApp.resolver.resolve(FetchGlucoseManager.self) {
            debug(.default, "🩸 Trigger FetchGlucoseManager")
            // fetchGlucose.fetch() // se ha un metodo pubblico
        }
        
        if let apsManager = FreeAPSApp.resolver.resolve(APSManager.self) {
            debug(.default, "⚙️ Trigger APSManager")
            // apsManager.heartbeat() // se ha un metodo pubblico
        }
        
        if let fetchTreatments = FreeAPSApp.resolver.resolve(FetchTreatmentsManager.self) {
            debug(.default, "💊 Trigger FetchTreatmentsManager")
            // fetchTreatments.fetch()
        }
    }
    
    // MARK: - API Call
    
    private func performAPICall(userInfo: [AnyHashable: Any], 
                                completion: @escaping (Bool) -> Void) {
        
        // Esempio di chiamata API personalizzata
        guard let url = URL(string: "https://api.tuoserver.com/sync") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25 // Lascia margine ai 30 secondi
        
        // Aggiungi dati dal payload se presenti
        var body: [String: Any] = [:]
        if let customData = userInfo["custom_data"] as? [String: Any] {
            body = customData
        }
        
        // Aggiungi info device
        body["device_token"] = UserDefaults.standard.string(forKey: "apnsDeviceToken") ?? ""
        body["timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                debug(.default, "❌ Errore API: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                debug(.default, "❌ Risposta non valida")
                completion(false)
                return
            }
            
            debug(.default, "📡 Risposta server: \(httpResponse.statusCode)")
            
            if (200...299).contains(httpResponse.statusCode) {
                if let data = data {
                    debug(.default, "✅ Dati ricevuti: \(data.count) bytes")
                    
                    // Parse risposta se necessario
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        debug(.default, "JSON: \(json)")
                    }
                }
                completion(true)
            } else {
                completion(false)
            }
        }
        
        task.resume()
    }
    
    // MARK: - Send Device Token to Server
    
    private func sendDeviceTokenToServer(_ token: String) {
        guard let url = URL(string: "https://api.tuoserver.com/register-device") else { 
            debug(.default, "⚠️ URL backend non configurato")
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "device_token": token,
            "platform": "ios",
            "app_version": Bundle.main.releaseVersionNumber ?? "unknown",
            "build_version": Bundle.main.buildVersionNumber ?? "unknown",
            "registered_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                debug(.default, "❌ Errore invio token: \(error)")
            } else if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    debug(.default, "✅ Token inviato al server con successo")
                } else {
                    debug(.default, "⚠️ Server ha risposto con status: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    // Gestisce notifiche quando app è in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let userInfo = notification.request.content.userInfo
        debug(.default, "📬 Notifica ricevuta in foreground: \(userInfo)")
        
        // Per silent push non mostrare nulla
        // Per notifiche normali mostra banner e suono
        if let aps = userInfo["aps"] as? [String: Any],
           aps["content-available"] as? Int == 1 {
            // Silent push - non mostrare nulla
            completionHandler([])
        } else {
            // Notifica normale - mostra
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    // Gestisce tap su notifica
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        debug(.default, "👆 Tap su notifica: \(userInfo)")
        
        // Gestisci azioni basate sulla notifica se necessario
        
        completionHandler()
    }
}