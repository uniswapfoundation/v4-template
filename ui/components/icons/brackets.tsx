import * as React from "react";
import { SVGProps } from "react";
const BracketsIcon = (props: SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={20}
    height={20}
    viewBox="0 0 20 20"
    fill="none"
    {...props}
  >
    <path
      stroke="currentColor"
      strokeLinecap="square"
      strokeWidth={1.667}
      d="M5.833 3.333h-2.5v13.334h2.5m8.333-13.334h2.5v13.334h-2.5"
    />
  </svg>
);
export default BracketsIcon;
