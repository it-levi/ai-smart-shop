// ========== CHATBOT ==========
function fakeChatbotResponse(userMessage) {
  const responses = {
    "hello": "Hi there! How can I help you today?",
    "price": "Our prices are very affordable!",
    "ai": "We use AI to make shopping smarter and easier.",
    "bye": "Goodbye! Come back soon.",
  };
  const lowerMsg = userMessage.toLowerCase();
  return responses[lowerMsg] || "Sorry, I didn't understand that.";
}

document.addEventListener("DOMContentLoaded", () => {
  const chatbot = document.getElementById("chatbot");
  const chatInput = document.getElementById("chatInput");
  const chatMessages = document.getElementById("chatMessages");

  if (chatbot && chatInput && chatMessages) {
    chatbot.addEventListener("submit", (e) => {
      e.preventDefault();
      const userMsg = chatInput.value;
      const botMsg = fakeChatbotResponse(userMsg);

      const userBubble = document.createElement("div");
      userBubble.textContent = "You: " + userMsg;
      const botBubble = document.createElement("div");
      botBubble.textContent = "Bot: " + botMsg;

      chatMessages.append(userBubble);
      chatMessages.append(botBubble);
      chatInput.value = "";

      speakText(botMsg);
    });
  }
});

// ========== SPEECH TO TEXT ==========
function startSpeechToText() {
  const recognition = new (window.SpeechRecognition || window.webkitSpeechRecognition)();
  recognition.lang = 'en-US';
  recognition.start();

  recognition.onresult = function(event) {
    const transcript = event.results[0][0].transcript;
    document.getElementById("chatInput").value = transcript;
  };

  recognition.onerror = function(event) {
    alert("Speech recognition error: " + event.error);
  };
}

// ========== TEXT TO SPEECH ==========
function speakText(text) {
  const speech = new SpeechSynthesisUtterance(text);
  speech.lang = 'en-US';
  window.speechSynthesis.speak(speech);
}

// ========== GOOGLE TRANSLATE ==========
function loadGoogleTranslate() {
  const gt = document.createElement("script");
  gt.src = "//translate.google.com/translate_a/element.js?cb=googleTranslateElementInit";
  document.body.appendChild(gt);

  window.googleTranslateElementInit = function() {
    new google.translate.TranslateElement({pageLanguage: 'en'}, 'google_translate_element');
  };
}

window.onload = loadGoogleTranslate;