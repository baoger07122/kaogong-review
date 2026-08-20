# 样式层

样式按原始级联顺序拆分，由 `build.js` 的 `CSS_MODULES` 依次拼接。
不要按文件名自行调整顺序；后面的规则可能是对前面规则的定向覆盖。

`71-sketch-preserved.css`、`90-speed-preserved.css` 和
`92-speed-preserved.css` 是受保护片段，只允许随构建拼接，不重写涂鸦和速算样式。
