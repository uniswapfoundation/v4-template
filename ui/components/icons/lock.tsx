import * as React from "react";
import { SVGProps } from "react";
const LockIcon = (props: SVGProps<SVGSVGElement>) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={20}
    height={20}
    viewBox="0 0 20 20"
    fill="none"
    {...props}
  >
    <path
      fill="currentColor"
      d="M4.167 8.333V7.5h-.833v.833h.833Zm11.667 0h.833V7.5h-.833v.833Zm0 9.167v.833h.833V17.5h-.833Zm-11.667 0h-.833v.833h.833V17.5ZM12.5 8.333a.833.833 0 0 0 1.667 0H12.5Zm-6.666 0a.833.833 0 1 0 1.666 0H5.834Zm5 3.334v-.834H9.167v.834h1.667Zm-1.667 2.5V15h1.667v-.833H9.167Zm-5-5.834v.834h11.667V7.5H4.167v.833Zm11.667 0H15V17.5H16.667V8.333h-.833Zm0 9.167v-.833H4.167v1.666h11.667V17.5Zm-11.667 0H5V8.333H3.334V17.5h.833Zm9.167-11.667H12.5v2.5H14.167v-2.5h-.833Zm-6.667 2.5H7.5v-2.5H5.834v2.5h.833ZM10 2.5v.833a2.5 2.5 0 0 1 2.5 2.5H14.167A4.167 4.167 0 0 0 10 1.667V2.5Zm0 0v-.833a4.167 4.167 0 0 0-4.166 4.166H7.5a2.5 2.5 0 0 1 2.5-2.5V2.5Zm0 9.167h-.833v2.5H10.834v-2.5H10Z"
    />
  </svg>
);
export default LockIcon;
