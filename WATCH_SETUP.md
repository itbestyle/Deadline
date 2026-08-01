# Watch MVP setup (Deadline)

В проект уже добавлены файлы watch MVP:

- `DeadlineWatch/DeadlineWatchApp.swift`
- `DeadlineWatch/WatchContentView.swift`
- `DeadlineWatch/WatchDeadlineStore.swift`
- `DeadlineWatch/WatchDeadlineModel.swift`

И данные с iPhone уже отправляются через `WatchConnectivityBridge` из `DeadlineViewModel`.

## 1) Добавить watch targets

1. Открой `DeadlinesApp.xcodeproj` в Xcode.
2. `File` → `New` → `Target...`.
3. Выбери `watchOS` → `Watch App for iOS App`.
4. Назови, например, `DeadlineWatch`.
5. Включи SwiftUI lifecycle (по умолчанию).

## 2) Подключить файлы в target membership

Для watch extension включи membership у:

- `DeadlineWatchApp.swift`
- `WatchContentView.swift`
- `WatchDeadlineStore.swift`
- `WatchDeadlineModel.swift`

Для iOS app membership должны остаться:

- `Deadline/WatchConnectivityBridge.swift`
- `Deadline/WatchDeadlinePayload.swift`
- `Deadline/DeadlineViewModel.swift`

## 3) Capability

Для iOS app и для watch extension добавь capability:

- `App Groups` (тот же group, что и в приложении)

> Для текущего обмена по `WCSession.updateApplicationContext` App Group не обязателен, но лучше держать capabilities согласованными.

## 4) Проверка

1. Запусти iOS app на iPhone simulator/device.
2. Запусти watch app на paired watch simulator/device.
3. Проверь, что на watch появляются:
   - секция `Pressure High` (<=24ч),
   - секция `Pressure Mid` (<=72ч),
   - пустое состояние без активных дедлайнов.

## 5) Что уже реализовано

- Передача массива дедлайнов с полем `pressure` (`critical/medium/low`) с iPhone.
- Сортировка по ближайшей дате на watch.
- Визуальные pressure-индикаторы в watch list.
- Pressure-индикаторы в widget accessory-видах (`inline/circular/rectangular`) и строках `systemSmall/systemMedium`.
