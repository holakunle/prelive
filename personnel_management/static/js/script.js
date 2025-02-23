document.addEventListener('DOMContentLoaded', () => {
    const details = document.querySelectorAll('details');
    details.forEach((targetDetail) => {
        targetDetail.addEventListener('click', () => {
            details.forEach((detail) => {
                if (detail !== targetDetail && detail.open) {
                    detail.open = false;
                }
            });
        });
    });
});