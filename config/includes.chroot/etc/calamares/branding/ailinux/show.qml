import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function nextSlide() { presentation.goToNextSlide() }

    Timer {
        interval: 7000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.nextSlide()
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0e1116" }
        Image {
            anchors.fill: parent
            source: "website-hero.jpg"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.19
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#C90e1116" }
                GradientStop { position: 1.0; color: "#E60e1116" }
            }
        }
        Column {
            width: parent.width * 0.78
            spacing: 18
            anchors.centerIn: parent
            Image {
                width: 132; height: 132
                anchors.horizontalCenter: parent.horizontalCenter
                source: "ailinux-logo.svg"
                fillMode: Image.PreserveAspectFit
            }
            Text {
                width: parent.width
                text: "AILinuX 26.04 LTS"
                color: "#e3e8f1"
                font.pixelSize: 42
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "AI-vernetztes Linux. Deine Freiheit bleibt."
                color: "#7bd7ff"
                font.pixelSize: 22
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0e1116" }
        Rectangle {
            width: parent.width * 0.84; height: parent.height * 0.70
            anchors.centerIn: parent
            radius: 22
            color: "#D9131822"
            border.color: "#263040"
            border.width: 1
        }
        Column {
            width: parent.width * 0.72
            spacing: 20
            anchors.centerIn: parent
            Text {
                width: parent.width
                text: "Wayland. Direkt ab Werk."
                color: "#e3e8f1"
                font.pixelSize: 38
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "Plasma Wayland, aktueller AILinuX-Kernel und ein Desktop ohne Legacy-Zwang."
                color: "#a9b3c0"
                font.pixelSize: 21
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Row {
                spacing: 16
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: [ "WAYLAND", "PLASMA", "KERNEL 7.2", "KVM READY" ]
                    Rectangle {
                        width: 132; height: 46; radius: 12
                        color: "#1b2330"
                        border.color: index % 2 === 0 ? "#3aa0ff" : "#44d19a"
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: index % 2 === 0 ? "#7bd7ff" : "#7bdcb5"
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0e1116" }
        Column {
            width: parent.width * 0.80
            spacing: 22
            anchors.centerIn: parent
            Text {
                width: parent.width
                text: "Deine AI-Werkzeuge sind schon da."
                color: "#e3e8f1"
                font.pixelSize: 36
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "AICoder, Copa OCR und das AILinuX-Ökosystem verbinden Desktop, Terminal und Modelle — ohne dich an einen Anbieter zu ketten."
                color: "#a9b3c0"
                font.pixelSize: 20
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Row {
                spacing: 22
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: [
                        { title: "AICoder", sub: "AI-Entwicklung" },
                        { title: "Copa OCR", sub: "Text aus jedem Bild" },
                        { title: "TriForce", sub: "Modelle & MCP" }
                    ]
                    Rectangle {
                        width: 210; height: 126; radius: 16
                        color: "#131822"
                        border.color: "#263040"
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: modelData.title; color: "#7bd7ff"; font.pixelSize: 22; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.sub; color: "#a9b3c0"; font.pixelSize: 15; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                    }
                }
            }
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0e1116" }
        Column {
            width: parent.width * 0.76
            spacing: 20
            anchors.centerIn: parent
            Image {
                width: 110; height: 110
                source: "ailinux-logo.svg"
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                width: parent.width
                text: "Dein System. Deine Regeln."
                color: "#e3e8f1"
                font.pixelSize: 40
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "Offene Paketquellen, lokale Kontrolle und volle Linux-Freiheit. Die Installation ist gleich abgeschlossen."
                color: "#a9b3c0"
                font.pixelSize: 21
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Rectangle {
                width: 320; height: 4; radius: 2
                color: "#263040"
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle { width: parent.width * 0.72; height: parent.height; radius: 2; color: "#44d19a" }
            }
        }
    }

    function onActivate() { presentation.currentSlide = 0 }
    function onLeave() {}
}
