const PAYMENT_PLANS = {
  PLAN_100: {
    code: 'PLN_2t2fvh0gmfjshy7',
    credits: 100,
  },
  PLAN_300: {
    code: 'PLN_ietxwof2rdpsfpt',
    credits: 300,
  },
  PLAN_700: {
    code: 'PLN_qq7y0nbwj2x75ff',
    credits: 700,
  },
};

const getCreditsByCode = (planCode) => {
  const plan = Object.values(PAYMENT_PLANS).find((p) => p.code === planCode);
  return plan ? plan.credits : null;
};

module.exports = {
  PAYMENT_PLANS,
  getCreditsByCode,
};
