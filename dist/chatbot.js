(() => {
  const root = document.querySelector("[data-chatbot]");
  if (!root) return;

  const launch = root.querySelector(".chatbot-launch");
  const panel = root.querySelector(".chatbot-panel");
  const close = root.querySelector(".chatbot-close");
  const messages = root.querySelector(".chatbot-messages");
  const quick = root.querySelector(".chatbot-quick");
  const form = root.querySelector(".chatbot-form");
  const input = root.querySelector("textarea");
  const send = form.querySelector("button");
  let previousResponseId = null;
  let demoMode = false;
  const enquiry = { step: 0, answers: {} };

  function setOpen(open) {
    launch.setAttribute("aria-expanded", String(open));
    panel.setAttribute("aria-hidden", String(!open));
    panel.classList.toggle("open", open);
    if (open) setTimeout(() => input.focus(), 120);
    else launch.focus();
  }

  function scrollToLatest() {
    messages.scrollTo({ top: messages.scrollHeight, behavior: "smooth" });
  }

  function addMessage(role, text, options = {}) {
    const wrapper = document.createElement("div");
    wrapper.className = `chat-message ${role}`;
    const bubble = document.createElement("p");
    bubble.textContent = text;
    if (options.summary) bubble.classList.add("chatbot-summary");
    wrapper.appendChild(bubble);
    if (options.actions) {
      const actions = document.createElement("div");
      actions.className = "chatbot-actions";
      [
        ["Contact form", "/contact/"],
        ["Email Mason", "mailto:mason@edgemediacreative.co.uk"],
        ["Instagram", "https://instagram.com/masethecreative"],
      ].forEach(([label, href]) => {
        const link = document.createElement("a");
        link.href = href;
        link.textContent = label;
        if (href.startsWith("http")) link.rel = "noopener";
        actions.appendChild(link);
      });
      wrapper.appendChild(actions);
    }
    messages.appendChild(wrapper);
    scrollToLatest();
    return wrapper;
  }

  function showTyping() {
    const typing = document.createElement("div");
    typing.className = "chat-message assistant typing";
    typing.innerHTML = "<p><i></i><i></i><i></i></p>";
    messages.appendChild(typing);
    scrollToLatest();
    return typing;
  }

  function setQuickReplies(labels = []) {
    quick.replaceChildren();
    labels.forEach(label => {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      button.addEventListener("click", () => submitMessage(label));
      quick.appendChild(button);
    });
  }

  function enquirySummary() {
    const a = enquiry.answers;
    const suggested = /monthly|regular|social/i.test(`${a.goal} ${a.project}`)
      ? "Monthly social content"
      : /event/i.test(a.project || "")
        ? "Event coverage"
        : /photo/i.test(a.project || "")
          ? "Photography"
          : /video|film/i.test(a.project || "")
            ? "Video production"
            : "To discuss with Mason";
    return `PROJECT ENQUIRY\nGoal: ${a.goal}\nProject: ${a.project}\nLocation: ${a.location}\nBudget: ${a.budget}\nPreferred start: ${a.timeframe}\nSuggested service: ${suggested}\nPricing and availability: To be confirmed personally by Mason.`;
  }

  function localReply(message) {
    const value = message.trim();
    const lower = value.toLowerCase();
    if (/content direction|content guidance|membership|create (it|content) myself|make (it|content) myself/.test(lower)) {
      return { text: "Content Direction by Mase is a paid monthly guidance membership for business owners who want to create better content themselves. It covers practical decisions around kit, software, workflow and what to make next—and helps you recognise when professional production would be worth bringing in. Pricing and subscription details are being finalised, so I won’t guess at them. You can register your interest through the contact form.", actions: true, quick: [] };
    }
    if (/\b(price|pricing|cost|how much)\b/.test(lower)) {
      return { text: "Monthly content starts from £250 per month. Other work is quoted individually because the scope can vary quite a bit. Mason will confirm the final price personally.\n\nWhat are you hoping to create?", quick: ["Monthly content", "Photography", "Video", "Event coverage"] };
    }
    if (/\b(where|location|area|based|travel)\b/.test(lower)) {
      return { text: "Mason works primarily across the Midlands, but UK-wide projects are considered depending on the brief. Where are you based?", quick: [] };
    }
    if (/\b(available|availability|date|when can)\b/.test(lower)) {
      return { text: "I can’t confirm Mason’s availability. Tell me the timeframe you have in mind and he’ll confirm it personally.", quick: ["Within a month", "1–3 months", "Later this year", "No fixed date"] };
    }
    if (/\b(email|contact|instagram|message)\b/.test(lower)) {
      return { text: "You can use the contact form, email mason@edgemediacreative.co.uk, or message @masethecreative on Instagram.", actions: true };
    }
    if (/what do you offer|services|what do you do/.test(lower)) {
      return { text: "Mase the Creative covers photography, video, monthly content, social media management, short-form content, commercial work, campaigns, launches and event coverage. Content Direction is the monthly guidance membership for businesses that want to create more content themselves.\n\nWhat are you trying to achieve?", quick: ["Create content myself", "More consistent content", "Launch something", "Cover an event"] };
    }

    if (enquiry.step === 0 && /regular|monthly/.test(lower)) {
      enquiry.answers.project = "Monthly content";
      return { text: "Monthly content sounds like the right area to explore. What would you like that content to achieve for the business?", quick: ["Build awareness", "Show the people behind it", "Promote products or services", "Stay consistent"] };
    }
    if (enquiry.step === 0) {
      enquiry.answers.goal = value;
      enquiry.step = enquiry.answers.project ? 2 : 1;
      return enquiry.answers.project
        ? { text: "Where is the business or project based?", quick: ["East Midlands", "West Midlands", "Elsewhere in the UK"] }
        : { text: "What sort of project do you have in mind?", quick: ["Photography", "Video", "Monthly content", "Social media management", "Event coverage", "Commercial"] };
    }
    if (enquiry.step === 1) {
      enquiry.answers.project = value;
      enquiry.step = 2;
      return { text: "Where is the business or project based?", quick: ["East Midlands", "West Midlands", "Elsewhere in the UK"] };
    }
    if (enquiry.step === 2) {
      enquiry.answers.location = value;
      enquiry.step = 3;
      return { text: "What approximate budget are you working with? A rough range is absolutely fine.", quick: ["Under £500", "£500–£1,000", "£1,000–£2,500", "£2,500+", "Not sure yet"] };
    }
    if (enquiry.step === 3) {
      enquiry.answers.budget = value;
      enquiry.step = 4;
      return { text: "When are you hoping to get started? I can collect the timeframe, but Mason will confirm availability personally.", quick: ["Within a month", "1–3 months", "Later this year", "No fixed date"] };
    }
    if (enquiry.step === 4) {
      enquiry.answers.timeframe = value;
      enquiry.step = 5;
      return { text: enquirySummary(), summary: true, actions: true, quick: [] };
    }
    return { text: "That summary is ready to send. Use whichever route is easiest and Mason can take it from there.", actions: true };
  }

  async function askApi(message) {
    const response = await fetch("/api/chat", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ message, previousResponseId }),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(data.error || "Assistant unavailable");
      error.demo = Boolean(data.demo) || response.status === 404;
      throw error;
    }
    previousResponseId = data.responseId || previousResponseId;
    return data.message;
  }

  async function submitMessage(value) {
    const message = value.trim();
    if (!message || send.disabled) return;
    addMessage("user", message);
    setQuickReplies();
    input.value = "";
    input.style.height = "auto";
    send.disabled = true;
    const typing = showTyping();
    try {
      if (!demoMode) {
        try {
          const reply = await askApi(message);
          typing.remove();
          const summary = reply.includes("PROJECT ENQUIRY");
          addMessage("assistant", reply, { summary, actions: summary });
          return;
        } catch (error) {
          if (!error.demo) throw error;
          demoMode = true;
        }
      }
      const reply = localReply(message);
      await new Promise(resolve => setTimeout(resolve, 320));
      typing.remove();
      addMessage("assistant", reply.text, reply);
      setQuickReplies(reply.quick);
    } catch {
      typing.remove();
      const item = addMessage("assistant", "I can’t reach the assistant just now. You can still contact Mason directly by email, through the form or on Instagram.", { actions: true });
      item.classList.add("chatbot-error");
    } finally {
      send.disabled = false;
      input.focus();
    }
  }

  launch.addEventListener("click", () => setOpen(launch.getAttribute("aria-expanded") !== "true"));
  close.addEventListener("click", () => setOpen(false));
  form.addEventListener("submit", event => { event.preventDefault(); submitMessage(input.value); });
  input.addEventListener("keydown", event => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      form.requestSubmit();
    }
  });
  input.addEventListener("input", () => {
    input.style.height = "auto";
    input.style.height = `${Math.min(input.scrollHeight, 112)}px`;
  });
  quick.querySelectorAll("button").forEach(button => button.addEventListener("click", () => submitMessage(button.textContent)));
  document.addEventListener("keydown", event => { if (event.key === "Escape" && panel.classList.contains("open")) setOpen(false); });
})();
