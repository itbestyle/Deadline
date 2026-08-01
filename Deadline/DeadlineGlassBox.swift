import SwiftUI

struct DeadlineGlassBox<Content: View>: View {
    let deadline: Deadline
    let color: Color
    var reducedEffects: Bool = false
    let content: () -> Content
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var intensityMultiplier: CGFloat {
        let statusScale: CGFloat = switch deadline.statusType {
        case .completed: 0.6
        case .cancelled: 0.5
        default: 1.0
        }
        let urgencyScale: CGFloat = reducedEffects ? 0.45 : 1.0
        return statusScale * urgencyScale
    }

    var body: some View {
        ZStack {
            // Внешнее свечение (ambient glow)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(0.25 * intensityMultiplier),
                            color.opacity(0.12 * intensityMultiplier),
                            color.opacity(0.05 * intensityMultiplier),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .blur(radius: 30)
                .scaleEffect(1.05)
            
            // Базовый цветной слой
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.18 * intensityMultiplier),
                            color.opacity(0.08 * intensityMultiplier),
                            color.opacity(0.12 * intensityMultiplier)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 25)
            
            // Основной glass layer
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    ZStack {
                        // Многослойный градиент
                        LinearGradient(
                            colors: [
                                colorScheme == .dark 
                                    ? Color.white.opacity(0.15)
                                    : Color.white.opacity(0.35),
                                Color.clear,
                                colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                        
                        // Цветной акцент
                        LinearGradient(
                            colors: [
                                color.opacity(0.25 * intensityMultiplier),
                                Color.clear,
                                Color.clear,
                                color.opacity(0.15 * intensityMultiplier)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        // Нижний градиент для глубины
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear,
                                            Color.black.opacity(colorScheme == .dark ? 0.15 : 0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 60)
                        }
                    }
                )
                // Внутренняя тень для глубины
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                        .blur(radius: 2)
                        .offset(y: 1)
                        .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                // Градиентная граница (убрана — убираем видимый контур)

                // Верхний основной блик
                .overlay(
                    VStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.25 : 0.45),
                                        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.25),
                                        Color.white.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 80)
                            .blur(radius: 12)
                            .padding(.horizontal, 30)
                            .padding(.top, 4)
                        
                        Spacer()
                    }
                )
                // Дополнительные мягкие блики
                .overlay(
                    GeometryReader { geometry in
                        ZStack {
                            // Левый верхний блик
                            Ellipse()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.5),
                                            Color.white.opacity(0.2),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 10,
                                        endRadius: 70
                                    )
                                )
                                .frame(width: 100, height: 100)
                                .offset(x: -30, y: -25)
                                .blur(radius: 15)
                            
                            // Средний блик (цветной)
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            color.opacity(0.3 * intensityMultiplier),
                                            color.opacity(0.15 * intensityMultiplier),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 15,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 120, height: 120)
                                .offset(x: geometry.size.width * 0.7, y: geometry.size.height * 0.3)
                                .blur(radius: 20)
                            
                            // Правый нижний блик
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            color.opacity(0.35 * intensityMultiplier),
                                            color.opacity(0.12 * intensityMultiplier),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 90
                                    )
                                )
                                .frame(width: 140, height: 140)
                                .offset(x: geometry.size.width - 40, y: geometry.size.height - 30)
                                .blur(radius: 25)
                            
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                )
                // Множественные тени для глубины
                .shadow(color: color.opacity(0.15 * intensityMultiplier), radius: 8, x: 0, y: 4)
                .shadow(color: color.opacity(0.25 * intensityMultiplier), radius: 20, x: 0, y: 10)
                .shadow(color: color.opacity(0.2 * intensityMultiplier), radius: 40, x: 0, y: 20)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                .shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 8)
                
                // Цветная полоска слева внутри glass-слоя
                .overlay(
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        color.opacity(0.8 * intensityMultiplier),
                                        color.opacity(0.5 * intensityMultiplier)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 3)
                            .padding(.vertical, 16)
                            .padding(.leading, 10)
                        
                        Spacer()
                    },
                    alignment: .leading
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }
}
