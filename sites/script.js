// 想起の瞬間。冒頭で一度見た文の英語を、押したときだけ出す。
// ページ自体が製品の循環を一度だけ実演する仕掛けなので、これ以外の動きは足さない。
document.querySelectorAll("[data-reveal]").forEach((button) => {
  button.addEventListener("click", () => {
    const answer = button.parentElement.querySelector("[data-answer]");
    if (!answer) return;
    answer.hidden = false;
    button.hidden = true;
  });
});
