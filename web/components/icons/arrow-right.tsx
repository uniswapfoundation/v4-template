import * as React from "react";
import { SVGProps } from "react";
const ArrowRightIcon = (props: SVGProps<SVGSVGElement>) => (
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
      d="m11.666 15 5-5-5-5m4.167 5h-12.5"
    />
  </svg>
);
export default ArrowRightIcon;
