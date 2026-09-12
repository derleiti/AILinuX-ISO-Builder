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
            opacity: 0.42
        }
        Rectangle {
            anchors.fill: parent
            color: "#8F0e1116"
        }
        Rectangle {
            width: parent.width * 0.82
            height: parent.height * 0.68
            anchors.centerIn: parent
            radius: 24
            color: "#131822"
            border.color: "#475569"
            border.width: 1
        }
        Column {
            width: parent.width * 0.70
            spacing: 18
            anchors.centerIn: parent
            Image {
                width: 126; height: 126
                anchors.horizontalCenter: parent.horizontalCenter
                source: "ailinux-logo.svg"
                fillMode: Image.PreserveAspectFit
            }
            Text {
                width: parent.width
                text: "AILinuX 26.04 LTS"
                color: "#ffffff"
                font.pixelSize: 42
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "AI-vernetztes Linux. Deine Freiheit bleibt."
                color: "#bae6fd"
                font.pixelSize: 22
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0e1116" }
        Image {
            anchors.fill: parent
            source: "installer-wallpaper.svg"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.48
        }
        Rectangle { anchors.fill: parent; color: "#990e1116" }
        Rectangle {
            width: parent.width * 0.84
            height: parent.height * 0.70
            anchors.centerIn: parent
            radius: 22
            color: "#131822"
            border.color: "#475569"
            border.width: 1
        }
        Column {
            width: parent.width * 0.72
            spacing: 20
            anchors.centerIn: parent
            Text {
                width: parent.width
                text: "Wayland. Direkt ab Werk."
                color: "#ffffff"
                font.pixelSize: 38
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "Plasma Wayland, aktueller AILinuX-Kernel und ein moderner Desktop mit voller Linux-Kontrolle."
                color: "#dbe4ee"
                font.pixelSize: 21
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Row {
                spacing: 16
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: [ "WAYLAND", "PLASMA", "AILINUX KERNEL", "KVM READY" ]
                    Rectangle {
                        width: 142; height: 46; radius: 12
                        color: "#1e293b"
                        border.color: index % 2 === 0 ? "#7dd3fc" : "#6ee7b7"
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: index % 2 === 0 ? "#e0f2fe" : "#d1fae5"
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0e1116" }
        Image {
            anchors.fill: parent
            source: "website-hero.jpg"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.34
        }
        Rectangle { anchors.fill: parent; color: "#A60e1116" }
        Rectangle {
            width: parent.width * 0.88
            height: parent.height * 0.72
            anchors.centerIn: parent
            radius: 22
            color: "#131822"
            border.color: "#475569"
            border.width: 1
        }
        Column {
            width: parent.width * 0.80
            spacing: 22
            anchors.centerIn: parent
            Text {
                width: parent.width
                text: "Deine AI-Werkzeuge sind schon da."
                color: "#ffffff"
                font.pixelSize: 36
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "AICoder, Copa OCR und das AILinuX-Ökosystem verbinden Desktop, Terminal und Modelle — ohne dich an einen Anbieter zu ketten."
                color: "#dbe4ee"
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
                        color: "#1e293b"
                        border.color: "#64748b"
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: modelData.title; color: "#bae6fd"; font.pixelSize: 22; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: modelData.sub; color: "#e2e8f0"; font.pixelSize: 15; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                    }
                }
            }
        }
    }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0e1116" }
        Image {
            anchors.fill: parent
            source: "installer-wallpaper.svg"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.46
        }
        Rectangle { anchors.fill: parent; color: "#A60e1116" }
        Rectangle {
            width: parent.width * 0.80
            height: parent.height * 0.66
            anchors.centerIn: parent
            radius: 22
            color: "#131822"
            border.color: "#475569"
            border.width: 1
        }
        Column {
            width: parent.width * 0.70
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
                color: "#ffffff"
                font.pixelSize: 40
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "Offene Paketquellen, lokale Kontrolle und volle Linux-Freiheit. Die Installation ist gleich abgeschlossen."
                color: "#dbe4ee"
                font.pixelSize: 21
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Rectangle {
                width: 320; height: 5; radius: 2
                color: "#334155"
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle { width: parent.width * 0.72; height: parent.height; radius: 2; color: "#6ee7b7" }
            }
        }
    }

    function onActivate() { presentation.currentSlide = 0 }
    function onLeave() {}
}
